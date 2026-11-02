import ArgumentParser
import Foundation
import HatsCore

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a profile and its launcher. Re-running keeps data and rebuilds the launcher."
    )

    @Argument(help: "Profile name: lowercase letters, digits and '-'.")
    var name: String

    @Option(help: "Display label (default: derived from the name).")
    var label: String?

    @Option(
        help: ArgumentHelp("Icon colour: \(ProfileColor.accepted) (default: picked from the name).", valueName: "color"),
        completion: .list(ProfileColor.named.map(\.name)))
    var color: String?

    @Option(
        help: ArgumentHelp(
            "Adopt an existing Claude Code config dir (e.g. ~/.claude-work) instead of creating one.",
            discussion: "Keeps its login, history and settings. hats never deletes an adopted dir.",
            valueName: "dir"
        ))
    var codeDir: String?

    @Option(help: "Launcher icon: letter, briefcase or person (default: picked from the name).")
    var icon: LauncherIcon?

    @Option(help: "A short name for the profile, e.g. w for work. add, rm and reset still take the full name.")
    var shortcut: String?

    @Flag(help: "Remove the profile's shortcut.")
    var noShortcut = false

    @Flag(help: "Also put a copy of the launcher on the Desktop.")
    var desktop = false

    @Flag(help: "Pin the launcher to the Dock (restarts the Dock).")
    var pin = false

    @Flag(help: "Open the profile right away, to sign in.")
    var open = false

    func validate() throws {
        guard shortcut == nil || !noShortcut else { throw ValidationError("give --shortcut or --no-shortcut, not both") }
    }

    func run() async throws {
        let context = try Context()
        let profileName = try ProfileName(name)
        let adopted = try codeDir.map { try context.directoryArgument($0, flag: "--code-dir") }
        let shortcutChange =
            noShortcut ? ShortcutChange.clear : try shortcut.map { ShortcutChange.set(try ProfileName(shortcut: $0)) }
        let (profile, created) = try context.store.create(
            profileName,
            label: label,
            color: try color.map { try ProfileColor(parsing: $0) },
            adoptingCodeDir: adopted,
            icon: icon,
            shortcut: shortcutChange
        )
        let launchers = context.launchers
        let bundle = try launchers.build(for: profile, hatsPath: context.hatsExecutablePath())

        print(created ? "Created profile '\(profile.name)'." : "Profile '\(profile.name)' already exists; launcher rebuilt.")
        print("  launcher  \(bundle.plainPath)")
        print("  desktop   \(profile.desktopDir.plainPath)")
        print("  code      \(profile.codeDir.plainPath)\(profile.codeDirIsExternal ? " (adopted)" : "")")
        if let shortcut = profile.shortcut { print("  shortcut  \(shortcut)") }
        if desktop { print("  copy      \(try launchers.copy(for: profile.name, to: context.layout.desktopFolder).plainPath)") }
        if pin { try context.pinToDock([profile], dedupeClaude: false) }
        if open {
            try await context.open(profile)
            print("\n" + Context.signInGuidance)
        }
        guard created, !open else { return }
        print(
            """

            Next:
              1. hats open \(profile.name)        (or double-click the launcher; hats dock pin \(profile.name) adds it to the Dock)
              2. Sign in. If the browser hands the login to another Claude window, quit the other
                 Claude windows (Cmd-Q), sign in, then reopen them with: hats open --all
              3. hats run \(profile.name)         then /login, to sign the claude CLI in to the same account
            """)
    }
}

extension LauncherIcon: ExpressibleByArgument {}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ls", abstract: "List profiles.", aliases: ["list"])

    @Flag(help: "Print JSON.")
    var json = false

    @Flag(help: "Also show disk usage per profile (slower; Cowork's VM alone is about 12 GB).")
    var size = false

    @Flag(help: "Show each profile's Desktop data dir and Claude Code config dir instead of its status. --json always includes them.")
    var paths = false

    struct Row: Encodable {
        let name: String
        let shortcut: String?
        let label: String
        let color: String
        let icon: LauncherIcon
        let desktopDir: String
        let codeDir: String
        let launcher: String?
        let cliLogin: CredentialState
        let account: AccountInfo
        let runningDesktop: Int
        let runningSessions: Int
        let diskBytes: Int64?

        private enum Key: String, CodingKey {
            case name, shortcut, label, color, icon, desktopDir, codeDir, launcher, cliLogin, account, runningDesktop, runningSessions,
                diskBytes
        }

        /// Part of the `--json` contract: a missing value prints as `null`.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(name, forKey: .name)
            try container.encode(shortcut, forKey: .shortcut)
            try container.encode(label, forKey: .label)
            try container.encode(color, forKey: .color)
            try container.encode(icon, forKey: .icon)
            try container.encode(desktopDir, forKey: .desktopDir)
            try container.encode(codeDir, forKey: .codeDir)
            try container.encode(launcher, forKey: .launcher)
            try container.encode(cliLogin, forKey: .cliLogin)
            try container.encode(account, forKey: .account)
            try container.encode(runningDesktop, forKey: .runningDesktop)
            try container.encode(runningSessions, forKey: .runningSessions)
            try container.encode(diskBytes, forKey: .diskBytes)
        }
    }

    func run() throws {
        let context = try Context()
        let profiles = try context.readableProfiles()
        if paths && !json { return printPaths(of: profiles) }
        let instances = InstanceScanner(profiles: profiles, processes: context.processes).scan().instances
        let probe = context.credentials
        let accounts = AccountProbe(layout: context.layout)
        let launchers = context.launchers
        let rows = profiles.map { profile in
            Row(
                name: profile.name.rawValue,
                shortcut: profile.shortcut?.rawValue,
                label: profile.label,
                color: profile.color.description,
                icon: profile.icon,
                desktopDir: profile.desktopDir.plainPath,
                codeDir: profile.codeDir.plainPath,
                launcher: launchers.status(for: profile.name)?.bundle.plainPath,
                cliLogin: probe.state(forConfigDir: profile.codeDir, isDefault: profile.isDefault),
                account: accounts.info(for: profile),
                runningDesktop: instances.count { $0.profile == profile.name && $0.kind == .desktop },
                runningSessions: instances.count { $0.profile == profile.name && $0.kind != .desktop },
                diskBytes: size ? diskBytes(of: profile) : nil
            )
        }
        if json { return try Output.printJSON(rows) }
        var headers = ["PROFILE", "DESKTOP", "SESSIONS", "DESKTOP LOGIN", "CLI LOGIN", "ACCOUNT", "LAUNCHER"]
        if size { headers.insert("DISK", at: 6) }
        Output.printTable(
            headers: headers,
            rows: rows.map { row in
                var cells = [
                    Self.nameCell(row.name, shortcut: row.shortcut),
                    row.runningDesktop > 0 ? "running" : "-",
                    String(row.runningSessions),
                    Self.describe(row.account.desktop),
                    row.cliLogin == .present ? "yes" : row.cliLogin == .absent ? "no" : "?",
                    Self.describe(row.account),
                    row.name == "default" ? "Claude.app" : (row.launcher == nil ? "missing" : "ok"),
                ]
                if let bytes = row.diskBytes { cells.insert(Output.bytes(bytes), at: 6) }
                return cells
            }
        )
    }

    /// In place of the status columns, not beside them: a row with both runs to about 200 columns and wraps on nearly every terminal.
    private func printPaths(of profiles: [Profile]) {
        var headers = ["PROFILE", "DESKTOP DIR", "CONFIG DIR"]
        if size { headers.insert("DISK", at: 1) }
        Output.printTable(
            headers: headers,
            rows: profiles.map { profile in
                var cells = [
                    Self.nameCell(profile.name.rawValue, shortcut: profile.shortcut?.rawValue),
                    Self.displayable(profile.desktopDir),
                    Self.displayable(profile.codeDir),
                ]
                if size { cells.insert(Output.bytes(diskBytes(of: profile)), at: 1) }
                return cells
            }
        )
    }

    private static func nameCell(_ name: String, shortcut: String?) -> String {
        shortcut.map { "\(name) (\($0))" } ?? name
    }

    /// A directory name can hold newlines and escape sequences, which would split the row or drive the terminal.
    /// `--json` keeps the exact path.
    private static func displayable(_ directory: URL) -> String {
        directory.plainPath.unicodeScalars.map { $0.properties.generalCategory == .control ? "?" : String($0) }.joined()
    }

    private func diskBytes(of profile: Profile) -> Int64 {
        DiskUsage.allocatedSize(of: profile.desktopDir) + DiskUsage.allocatedSize(of: profile.codeDir)
    }

    static func describe(_ signIn: AccountInfo.SignIn) -> String {
        switch signIn {
        case .signedIn: "yes"
        case .signedOut: "no"
        case .neverOpened: "never opened"
        case .unknown: "?"
        }
    }

    /// The CLI's account email is the only human-readable identity on disk;
    /// Desktop records just an account ID.
    static func describe(_ account: AccountInfo) -> String {
        let identity = [account.codeEmail, account.codeOrganization.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
        let base = identity.isEmpty ? "-" : identity
        return account.isSplit ? base + " [Desktop on another account]" : base
    }
}

struct Open: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Focus each profile's Claude Desktop, or launch it.", aliases: ["o"])

    @Argument(help: "Profile names (use 'default' for the stock install).")
    var names: [String] = []

    @Flag(help: "Open every profile except default.")
    var all = false

    func validate() throws {
        guard all != !names.isEmpty else { throw ValidationError("give profile names or --all, not both or neither") }
    }

    func run() async throws {
        let context = try Context()
        let targets = all ? try context.readableProfiles().filter { !$0.isDefault } : try names.map { try context.profile($0) }
        if targets.isEmpty { return print("No profiles yet. Create one with: hats add <name>") }
        for target in targets { try await context.open(target) }
    }
}

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove a profile's launcher; with --purge, also move its data to the Trash.",
        aliases: ["remove"]
    )

    @Argument(help: "Profile names.")
    var names: [String] = []

    @Flag(help: "Remove the launchers of every profile (data is kept unless --purge).")
    var all = false

    @Flag(help: "Also move the profile's Desktop and Code data to the Trash. An adopted code dir is kept.")
    var purge = false

    @Flag(help: "Skip the typed confirmation for --purge.")
    var yes = false

    @Flag(help: "Remove the launcher even if the profile is running. Never purges a running profile.")
    var force = false

    @Flag(help: "Show what would be removed, change nothing.")
    var dryRun = false

    func validate() throws {
        guard all != !names.isEmpty else { throw ValidationError("give profile names or --all, not both or neither") }
    }

    func run() throws {
        let context = try Context()
        let targets =
            all
            ? try context.readableProfiles().filter { !$0.isDefault }
            : try names.map { try context.store.profile(fullName: $0) }
        if targets.contains(where: \.isDefault) {
            throw HatsError(.usage, "the default profile is the stock Claude install; hats never removes it")
        }
        for target in targets { try remove(target, context: context) }
    }

    private func remove(_ target: Profile, context: Context) throws {
        if purge {
            try context.refuseIfRunning(target, action: "purge it")
        } else if !force {
            try context.refuseIfRunning(target, action: "remove it (or pass --force to remove only the launcher)")
        }
        if dryRun {
            print("Would remove the launcher of '\(target.name)'.")
            if purge { print("Would move \(context.layout.profileDir(target.name).plainPath) to the Trash.") }
            return
        }

        if purge, !yes {
            guard isatty(STDIN_FILENO) != 0 else {
                throw HatsError(.usage, "--purge needs confirmation", hint: "pass --yes when running non-interactively")
            }
            print("This moves all local data of '\(target.name)' (\(context.layout.profileDir(target.name).plainPath)) to the Trash.")
            print("Type the profile name to confirm: ", terminator: "")
            guard readLine()?.trimmingCharacters(in: .whitespaces) == target.name.rawValue else {
                throw HatsError(.usage, "confirmation did not match; nothing was deleted")
            }
        }

        try context.launchers.remove(for: target.name)
        print("Removed launcher for '\(target.name)'.")
        if purge {
            try context.store.purge(target.name, processes: context.processes, discarder: context.touchpoints.discarder)
            print("Moved the data of '\(target.name)' to the Trash.")
            if target.codeDirIsExternal {
                print("Kept the adopted Claude Code dir \(target.codeDir.plainPath).")
            }
            if !target.codeDirIsExternal, context.credentials.state(forConfigDir: target.codeDir, isDefault: false) == .present {
                let service = KeychainCredentialProbe.serviceName(forConfigDir: target.codeDir, isDefault: false)
                print("Note: the CLI login stays in your Keychain as '\(service)'. Delete it in Keychain Access if you no longer need it.")
            }
        } else {
            print("Data kept in \(context.layout.profileDir(target.name).plainPath). Re-create the launcher with: hats add \(target.name)")
        }
    }
}

struct Launcher: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage launcher apps.",
        subcommands: [Rebuild.self, Copy.self, Reveal.self]
    )

    struct Copy: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Put copies of launchers somewhere else, such as the Desktop.")

        @Argument(help: "Profiles whose launchers to copy.")
        var names: [String]

        @Option(help: "Destination folder (default: ~/Desktop).")
        var to: String?

        func run() throws {
            let context = try Context()
            let destination = try to.map { try context.directoryArgument($0, flag: "--to") } ?? context.layout.desktopFolder
            let builder = context.launchers
            for name in names {
                print("Copied to \(try builder.copy(for: try context.profile(name).name, to: destination).plainPath)")
            }
        }
    }

    struct Reveal: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show the launchers folder in Finder.")

        func run() throws {
            let context = try Context()
            try revealLaunchers(layout: context.layout, opener: context.touchpoints.folderOpener)
        }
    }

    struct Rebuild: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Regenerate launchers (all profiles by default).")

        @Argument(help: "Profiles to rebuild.")
        var names: [String] = []

        func run() throws {
            let context = try Context()
            let targets =
                names.isEmpty
                ? try context.readableProfiles().filter { !$0.isDefault }
                : try names.map { try context.profile($0) }
            let builder = context.launchers
            let hatsPath = context.hatsExecutablePath()
            for profile in targets where !profile.isDefault {
                print("Rebuilt \(try builder.build(for: profile, hatsPath: hatsPath).plainPath)")
            }
        }
    }
}
