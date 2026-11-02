import Foundation

public struct Finding: Codable, Equatable, Sendable {
    public enum Level: String, Codable, Sendable, Comparable {
        case ok, warn, fail

        private var rank: Int { self == .ok ? 0 : self == .warn ? 1 : 2 }
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rank < rhs.rank }
    }

    public let level: Level
    public let check: String
    public let message: String
    public let hint: String?

    public init(_ level: Level, _ check: String, _ message: String, hint: String? = nil) {
        self.level = level
        self.check = check
        self.message = message
        self.hint = hint
    }
}

/// Read-only health checks. Never writes anything.
public struct Doctor: Sendable {
    let layout: Layout
    let store: ProfileStore
    let processes: any ProcessTable
    let credentials: any CredentialProbe
    let environment: [String: String]
    let urlSchemeHandler: @Sendable (String) -> URL?
    let install: HatsInstall?

    public init(
        layout: Layout,
        processes: any ProcessTable,
        credentials: any CredentialProbe,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        urlSchemeHandler: @escaping @Sendable (String) -> URL? = Doctor.systemURLSchemeHandler,
        install: HatsInstall? = nil
    ) {
        self.layout = layout
        store = ProfileStore(layout: layout)
        self.processes = processes
        self.credentials = credentials
        self.environment = environment
        self.urlSchemeHandler = urlSchemeHandler
        self.install = install
    }

    #if canImport(CoreServices)
    public static let systemURLSchemeHandler: @Sendable (String) -> URL? = { scheme in
        URL(string: "\(scheme)://").flatMap { LSCopyDefaultApplicationURLForURL($0 as CFURL, .all, nil)?.takeRetainedValue() as URL? }
    }
    #else
    public static let systemURLSchemeHandler: @Sendable (String) -> URL? = { _ in nil }
    #endif

    public func run() -> [Finding] {
        var findings = environmentFindings()
        let inventory: ProfileInventory
        do {
            inventory = try store.inventory()
        } catch {
            return findings + [Finding(.fail, "profiles", error.message, hint: error.hint)]
        }
        let profiles = inventory.profiles
        let accounts = Dictionary(uniqueKeysWithValues: profiles.map { ($0.name, AccountProbe(layout: layout).info(for: $0)) })
        findings += profiles.flatMap { profileFindings($0, account: accounts[$0.name]!) }
        findings += inventory.unreadableProfiles.map { Finding(.fail, "profile:\($0.name)", $0.error.message, hint: $0.error.hint) }
        findings += sharedAccountFindings(profiles, accounts: accounts)
        findings += shortcutFindings(profiles)
        findings += instanceFindings(profiles)
        return findings
    }

    private func environmentFindings() -> [Finding] {
        var findings: [Finding] = []
        if let install { findings.append(installFinding(install)) }
        do {
            let app = try ClaudeApp.locate(layout: layout, environment: environment)
            findings.append(Finding(.ok, "claude-app", "Claude Desktop \(app.version ?? "(unknown version)") at \(app.url.plainPath)"))
        } catch {
            findings.append(Finding(.fail, "claude-app", error.message, hint: error.hint))
        }
        if let cli = ExecutableLocator.find("claude", override: environment["HATS_CLAUDE_BIN"], environment: environment) {
            findings.append(Finding(.ok, "claude-cli", "claude CLI at \(cli.plainPath)"))
        } else {
            findings.append(
                Finding(
                    .warn, "claude-cli", "claude CLI not found on PATH",
                    hint: "needed only for 'hats run'; see https://code.claude.com/docs"))
        }
        let defaultCode = layout.defaultCodeDir.plainPath
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: defaultCode) {
            findings.append(
                Finding(
                    .warn, "default-profile",
                    "\(defaultCode) is a symlink to \(destination), so another tool manages it",
                    hint: "'default' then means whatever that tool selected, not the stock install"
                ))
        }
        findings.append(signInHandlerFinding())
        if let inherited = environment["CLAUDE_CONFIG_DIR"], !inherited.isEmpty {
            findings.append(Finding(.ok, "shell", "this shell has CLAUDE_CONFIG_DIR=\(inherited)"))
        }
        return findings
    }

    /// Browser sign-ins come back as a `claude://` link to whichever app owns
    /// the scheme. hats never changes that registration.
    private func installFinding(_ install: HatsInstall) -> Finding {
        let channel = InstallChannel.detect(executable: install.executable, layout: layout)
        let upgrade = channel.upgradeCommand(home: layout.home.plainPath).map { "; upgrade with: \($0)" } ?? ""
        return Finding(.ok, "install", "hats \(install.version) at \(install.executable.plainPath), \(channel.installedWith)\(upgrade)")
    }

    private func signInHandlerFinding() -> Finding {
        guard let handler = urlSchemeHandler("claude") else {
            return Finding(
                .warn, "sign-in", "no app handles claude:// links, so browser sign-ins cannot return to Claude",
                hint: "open Claude.app once so macOS registers it")
        }
        let bundleID = Bundle(url: handler)?.bundleIdentifier
        guard bundleID == ClaudeApp.bundleIdentifier else {
            return Finding(
                .warn, "sign-in", "claude:// links open \(handler.plainPath) (\(bundleID ?? "unknown")), not Claude Desktop",
                hint: "sign-ins from the browser may land in the wrong app")
        }
        return Finding(.ok, "sign-in", "claude:// links open \(handler.plainPath)")
    }

    private func profileFindings(_ profile: Profile, account: AccountInfo) -> [Finding] {
        let check = "profile:\(profile.name)"
        var findings: [Finding] = []
        let fm = FileManager.default
        if !profile.isDefault {
            for dir in [profile.desktopDir, profile.codeDir] where !fm.fileExists(atPath: dir.plainPath) {
                findings.append(Finding(.fail, check, "missing \(dir.plainPath)", hint: "re-create it with: hats add \(profile.name)"))
            }
            findings.append(contentsOf: launcherFindings(profile, check: check))
        }
        switch credentials.state(forConfigDir: profile.codeDir, isDefault: profile.isDefault) {
        case .present:
            findings.append(Finding(.ok, check, "Claude Code login present"))
        case .absent:
            findings.append(
                Finding(
                    .warn, check, "Claude Code is not logged in",
                    hint: profile.isDefault ? "run: claude, then /login" : "run: hats run \(profile.name), then /login"
                ))
        case .unknown:
            findings.append(Finding(.warn, check, "could not query the Keychain for the Claude Code login"))
        }
        findings.append(contentsOf: desktopAccountFindings(profile, account: account, check: check))
        return findings
    }

    private func desktopAccountFindings(_ profile: Profile, account: AccountInfo, check: String) -> [Finding] {
        var findings: [Finding] = []
        switch account.desktop {
        case .signedIn:
            findings.append(Finding(.ok, check, "Claude Desktop signed in"))
        case .signedOut:
            findings.append(Finding(.warn, check, "Claude Desktop is signed out", hint: "run: hats open \(profile.name), then sign in"))
        case .neverOpened:
            if !profile.isDefault {
                findings.append(
                    Finding(.warn, check, "Claude Desktop was never opened", hint: "run: hats open \(profile.name), then sign in"))
            }
        case .unknown:
            findings.append(Finding(.warn, check, "cannot read Claude Desktop's config.json; Claude may have changed its format"))
        }
        if account.isSplit {
            let who = account.codeEmail.map { " (\($0))" } ?? ""
            findings.append(
                Finding(
                    .warn, check,
                    "Claude Desktop and Claude Code\(who) are signed in to different accounts, so terminal sessions bill another account than the Desktop app",
                    hint: profile.isDefault ? "run: claude, then /login" : "run: hats run \(profile.name), then /login"
                ))
        }
        return findings
    }

    /// Two profiles on one account usually means a sign-in landed in the
    /// wrong window.
    private func sharedAccountFindings(_ profiles: [Profile], accounts: [ProfileName: AccountInfo]) -> [Finding] {
        let byAccount = Dictionary(grouping: profiles.filter { accounts[$0.name]?.accountID != nil }) { accounts[$0.name]!.accountID! }
        return byAccount.values.filter { $0.count > 1 }.sorted { $0[0].name < $1[0].name }.map { group in
            let names = group.map(\.name.rawValue)
            let resettable = group.first { !$0.isDefault }?.name.rawValue ?? names[1]
            return Finding(
                .warn, "accounts", "profiles \(names.joined(separator: ", ")) are signed in to the same Claude account",
                hint: "if one of them should use another account, run: hats reset \(resettable)")
        }
    }

    /// `add` refuses these, but a hand edit or a profile put back from the Trash
    /// gets past it. Then `ls` can suggest a different account from the one
    /// that a command runs on, or a command refuses with no sign why.
    private func shortcutFindings(_ profiles: [Profile]) -> [Finding] {
        let claims = Dictionary(grouping: profiles.filter { $0.shortcut != nil }) { $0.shortcut! }
        var findings: [Finding] = []
        for (shortcut, owners) in claims.sorted(by: { $0.key < $1.key }) {
            if profiles.contains(where: { $0.name == shortcut }) {
                for owner in owners where owner.name != shortcut {
                    let message = "the shortcut '\(shortcut)' of profile '\(owner.name)' is also a profile's name, which wins"
                    findings.append(Finding(.warn, "shortcuts", message, hint: "remove it with: hats add \(owner.name) --no-shortcut"))
                }
            } else if owners.count > 1 {
                let names = owners.map(\.name.rawValue).sorted()
                let message = "profiles \(names.joined(separator: ", ")) claim the shortcut '\(shortcut)', so commands refuse it"
                findings.append(
                    Finding(.warn, "shortcuts", message, hint: "keep it on one of them, for example: hats add \(names[0]) --no-shortcut"))
            }
        }
        return findings
    }

    private func launcherFindings(_ profile: Profile, check: String) -> [Finding] {
        guard let launcher = LauncherBuilder(layout: layout).status(for: profile.name) else {
            return [Finding(.warn, check, "no launcher", hint: "create it with: hats launcher rebuild \(profile.name)")]
        }
        if !launcher.hatsExecutableExists {
            return [
                Finding(
                    .fail, check, "launcher points to a missing hats binary (\(launcher.marker.hatsPath))",
                    hint: "run: hats launcher rebuild")
            ]
        }
        if let target = install?.launcherTarget,
            URL(filePath: launcher.marker.hatsPath).canonicalPath != URL(filePath: target).canonicalPath
        {
            return [
                Finding(
                    .warn, check, "launcher calls \(launcher.marker.hatsPath) instead of \(target)",
                    hint: "run: hats launcher rebuild")
            ]
        }
        if !launcher.isCurrent {
            return [Finding(.warn, check, "launcher is outdated", hint: "run: hats launcher rebuild")]
        }
        return [Finding(.ok, check, "launcher \(launcher.bundle.plainPath)")]
    }

    private func instanceFindings(_ profiles: [Profile]) -> [Finding] {
        let scan = InstanceScanner(profiles: profiles, processes: processes).scan()
        var findings: [Finding] = []
        let desktops = scan.instances.filter { $0.kind == .desktop }
        for duplicate in DuplicateInstances.groups(in: scan.instances) {
            let all = [duplicate.keep] + duplicate.extras
            let owner = duplicate.keep.profile.map { "profile '\($0)'" } ?? duplicate.dataDir
            let afterUpdate =
                duplicate.keep.profile?.isDefault == true
                ? "; a Claude update can relaunch a profile's window on the default profile, so reopen yours with: hats open --all" : ""
            findings.append(
                Finding(
                    .warn, "instances",
                    "\(all.count) Desktop instances share \(owner) (pids \(all.map { String($0.pid) }.joined(separator: ", ")))",
                    hint: "two instances on one data dir can corrupt it; quit the newer ones with: hats dedupe\(afterUpdate)"
                ))
        }
        for (name, group) in Dictionary(grouping: desktops.filter { $0.profile != nil }, by: { $0.profile! }).sorted(by: { $0.key < $1.key }
        ) {
            guard let profile = profiles.first(where: { $0.name == name }), !profile.isDefault else { continue }
            for instance in group where instance.configDir.map({ URL(filePath: $0).canonicalPath }) != profile.codeDir.canonicalPath {
                findings.append(
                    Finding(
                        .fail, "instances",
                        "Desktop pid \(instance.pid) for '\(name)' runs without its CLAUDE_CONFIG_DIR, so its Code tab may use another profile's state",
                        hint: "quit it and reopen with: hats open \(name)"
                    ))
            }
        }
        let unmanagedConfigDirs = Set(scan.instances.filter { $0.kind != .desktop && $0.profile == nil }.map(\.dataDir))
        for dir in unmanagedConfigDirs.sorted() {
            let name = ProfileName.suggested(forConfigDir: URL(filePath: dir))?.unlessShortcut(in: profiles)?.rawValue ?? "<name>"
            findings.append(
                Finding(
                    .warn, "instances",
                    "Claude Code sessions run with an unmanaged config dir \(dir)",
                    hint: "adopt it with: hats add \(name) --code-dir \(dir)"
                ))
        }
        for instance in desktops where instance.profile == nil {
            findings.append(Finding(.warn, "instances", "Desktop pid \(instance.pid) uses an unmanaged data dir \(instance.dataDir)"))
        }
        if !scan.undecodableRegistryFiles.isEmpty {
            findings.append(
                Finding(
                    .warn, "instances",
                    "\(scan.undecodableRegistryFiles.count) Claude Code session files could not be read; Claude Code may have changed its format",
                    hint: "please report your Claude Code version at https://github.com/wearhats/hats/issues"
                ))
        }
        if findings.isEmpty {
            findings.append(
                Finding(
                    .ok, "instances",
                    "\(desktops.count) Desktop and \(scan.instances.count - desktops.count) Claude Code instances, no conflicts"))
        }
        return findings
    }
}
