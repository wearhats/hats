#if os(macOS)
import Darwin
import Foundation

/// hats' own end-to-end test mode, switched on by `HATS_TEST_SANDBOX=<dir>`. It
/// only narrows what hats does: every OS touchpoint becomes a file inside `<dir>`
/// or a record of the call, and other processes are invisible unless their
/// executable lies inside `<dir>`. A half-configured sandbox refuses to start, so
/// it can't fall through to the real Dock, Trash or Claude.
public struct TestSandbox: Sendable {
    public static let variable = "HATS_TEST_SANDBOX"
    /// Must exist in `<dir>`, so the switch can't be pointed at a folder with real
    /// data in it, where real Claude processes would be invisible and the refusals
    /// for a running profile wouldn't fire.
    public static let markerFile = ".hats-test-sandbox"
    /// Set to `guarded`, real launches, activation and quits happen, but only for
    /// apps and PIDs inside `<dir>`, so a test can't reach a real Claude window.
    public static let appControlVariable = "HATS_TEST_APP_CONTROL"
    /// `launch` starts nothing in test mode, so no real PID exists to report.
    static let launchedPID: Int32 = 99_999

    let root: String
    private let usesRealAppControl: Bool

    /// `nil` when test mode is off. Throws when it is on but can't be contained.
    public init?(environment: [String: String], layout: Layout) throws(HatsError) {
        guard let raw = environment[Self.variable] else {
            // Asking for the guarded mode must never quietly mean the real one.
            if environment[Self.appControlVariable] != nil { throw Self.refusal("\(Self.appControlVariable) needs \(Self.variable)") }
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: raw, isDirectory: &isDirectory), isDirectory.boolValue,
            let root = Self.canonical(raw)
        else {
            throw Self.refusal("\(Self.variable) is not an existing directory: '\(raw)'")
        }
        // A root this wide would make the containment checks below meaningless.
        guard let realHome = NSHomeDirectoryForUser(NSUserName()).flatMap(Self.canonical), root != "/",
            !Self.isInside(realHome, root: root)
        else {
            throw Self.refusal("\(Self.variable) must not contain the real home directory: '\(root)'")
        }
        guard FileManager.default.fileExists(atPath: root + "/" + Self.markerFile) else {
            throw Self.refusal("\(Self.variable) has no \(Self.markerFile) file: '\(root)'")
        }
        self.root = root
        switch environment[Self.appControlVariable] {
        case nil: usesRealAppControl = false
        case "guarded": usesRealAppControl = true
        case let other?: throw Self.refusal("\(Self.appControlVariable) must be 'guarded', not '\(other)'")
        }

        for variable in ["HOME", "HATS_HOME", "HATS_LAUNCHER_DIR"] where (environment[variable] ?? "").isEmpty {
            throw Self.refusal("\(Self.variable) needs \(variable) set inside it")
        }
        let resolved = [
            "HOME": layout.home, "HATS_HOME": layout.hatsHome, "HATS_LAUNCHER_DIR": layout.launcherDir,
            "HATS_DEFAULT_CONFIG_DIR": layout.defaultCodeDir,
        ]
        for (variable, url) in resolved.sorted(by: { $0.key < $1.key }) {
            try requireInside(url.plainPath, what: variable)
        }
        for variable in ["HATS_CLAUDE_APP", "HATS_CLAUDE_BIN"] {
            if let value = environment[variable], !value.isEmpty { try requireInside(value, what: variable) }
        }
        try requireStoredPathsInside(layout: layout)
    }

    /// Paths also come from what's on disk: a symlink below a root, an adopted dir
    /// in `profile.json`, a copy recorded in a launcher's marker. hats follows all
    /// of them, so they get the same check as the environment.
    private func requireStoredPathsInside(layout: Layout) throws(HatsError) {
        var paths = [
            ("the Desktop folder", layout.desktopFolder), ("the profiles dir", layout.profilesDir),
            ("the default Desktop dir", layout.defaultDesktopDir),
            ("the stand-ins' dir", URL(filePath: root, directoryHint: .isDirectory).appending(path: ".test")),
        ]
        // A listing that can't be read leads nowhere, and each command must still
        // report that failure its own way.
        for profile in (try? ProfileStore(layout: layout).inventory().profiles) ?? [] where !profile.isDefault {
            paths += [("the Desktop dir of '\(profile.name)'", profile.desktopDir), ("the code dir of '\(profile.name)'", profile.codeDir)]
        }
        for launcher in (try? LauncherBuilder.reading(layout: layout).installed()) ?? [] {
            paths.append(("the launcher of '\(launcher.marker.name)'", launcher.bundle))
            paths += launcher.copies.map { ("a recorded copy of '\(launcher.marker.name)'", $0) }
        }
        for (what, url) in paths { try requireInside(url.plainPath, what: what) }
    }

    public func requireInside(_ path: String, what: String) throws(HatsError) {
        guard Self.canonical(path).map({ Self.isInside($0, root: root) }) == true else {
            throw Self.refusal("\(what) is outside \(Self.variable): '\(path)'")
        }
    }

    public var touchpoints: Touchpoints {
        Touchpoints(
            processes: SandboxedProcessTable(sandbox: self),
            control: usesRealAppControl ? GuardedAppControl(sandbox: self) : RecordingAppControl(sandbox: self, log: log),
            credentials: SeededCredentialProbe(file: file("keychain.json")),
            dock: FileDockPreferences(file: file("dock.plist"), log: log),
            discarder: discarder,
            registrar: AppRegistrar { [log] bundle in log.record("register", ["path": bundle.plainPath]) },
            folderOpener: RecordingFolderOpener(log: log),
            urlSchemeHandler: { [handlerFile = file("claude-url-handler")] _ in
                (try? String(contentsOf: handlerFile, encoding: .utf8)).map {
                    URL(filePath: $0.trimmingCharacters(in: .whitespacesAndNewlines), directoryHint: .isDirectory)
                }
            },
            appSearch: .nowhere,
            releaseFeed: nil
        )
    }

    private var log: TestEventLog { TestEventLog(file: file("events.jsonl")) }

    private var discarder: Discarder {
        Discarder { [root, log, trash = file("trash")] url in
            let path = url.plainPath
            guard Self.canonical(path).map({ Self.isInside($0, root: root) }) == true else {
                throw Self.refusal("refusing to discard \(path): outside \(Self.variable)")
            }
            let slot = trash.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            let destination = slot.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            log.record("trash", ["path": path, "to": destination.plainPath])
        }
    }

    private func file(_ name: String) -> URL {
        URL(filePath: root, directoryHint: .isDirectory).appending(path: ".test/\(name)")
    }

    func ownsExecutable(of pid: Int32) -> Bool {
        executable(of: pid).map { Self.isInside($0, root: root) } ?? false
    }

    /// Bundled like a real app, so a helper binary in `<dir>` isn't taken for one.
    func isRegularApp(pid: Int32) -> Bool {
        executable(of: pid).map { Self.isInside($0, root: root) && $0.contains(".app/Contents/MacOS/") } ?? false
    }

    private func executable(of pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return Self.canonical(String(decoding: buffer.prefix(Int(length)), as: UTF8.self))
    }

    private static func refusal(_ message: String) -> HatsError {
        HatsError(.environment, message, hint: "\(variable) is only for hats' own tests; unset it to use hats normally")
    }

    /// Compares `realpath` results rather than `URL.canonicalPath`, which strips
    /// the `/private` prefix `proc_pidpath` reports.
    private static func isInside(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    /// `realpath` of the deepest part that exists, plus the rest, since a
    /// destination such as a new `--to` folder needn't exist yet. `nil` for what
    /// can't be resolved safely: a dangling symlink could point anywhere, and
    /// `..` after a missing component has no real meaning.
    static func canonical(_ path: String) -> String? {
        var existing = (path as NSString).isAbsolutePath ? path : FileManager.default.currentDirectoryPath + "/" + path
        var missing: [String] = []
        while true {
            if let resolved = realpath(existing, nil) {
                defer { free(resolved) }
                return ([String(cString: resolved)] + missing).joined(separator: "/")
            }
            var status = stat()
            guard lstat(existing, &status) != 0, errno == ENOENT else { return nil }
            let last = (existing as NSString).lastPathComponent
            let parent = (existing as NSString).deletingLastPathComponent
            guard last != "..", parent != existing, !parent.isEmpty else { return nil }
            missing.insert(last, at: 0)
            existing = parent
        }
    }
}

/// One JSON object per line, in call order, so a test can assert what hats asked
/// the OS to do and in which order.
struct TestEventLog: Sendable {
    let file: URL

    func record(_ event: String, _ fields: [String: any Sendable] = [:]) {
        var object: [String: Any] = fields
        object["event"] = event
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var line = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            line.append(0x0A)
            let descriptor = open(file.plainPath, O_WRONLY | O_CREAT | O_APPEND, 0o600)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: line)
        } catch {
            // A lost record would make a test pass on a call it never saw.
            fatalError("cannot record \(event) in \(file.plainPath): \(error)")
        }
    }
}

/// `summaries()` stays real because walking up to a host app needs real parents,
/// and it exposes only PID, parent, start time and name. Checking the path first
/// means test mode never reads another process's environment block.
struct SandboxedProcessTable: ProcessTable {
    let sandbox: TestSandbox
    private let real = DarwinProcessTable()

    func summaries() -> [ProcessSummary] { real.summaries() }

    func details(of pid: Int32) -> ProcessDetails? {
        sandbox.ownsExecutable(of: pid) ? real.details(of: pid) : nil
    }
}

struct RecordingAppControl: AppControl {
    let sandbox: TestSandbox
    let log: TestEventLog

    func launch(appURL: URL, newInstance: Bool, arguments: [String], environment: [String: String]) async throws -> Int32 {
        try sandbox.requireInside(appURL.plainPath, what: "the app to launch")
        log.record("launch", ["app": appURL.plainPath, "newInstance": newInstance, "arguments": arguments, "environment": environment])
        return TestSandbox.launchedPID
    }

    @MainActor func activate(pid: Int32) -> Bool {
        guard sandbox.isRegularApp(pid: pid) else { return false }
        log.record("activate", ["pid": pid])
        return true
    }

    @MainActor func isRegularApp(pid: Int32) -> Bool { sandbox.isRegularApp(pid: pid) }

    @MainActor func terminate(pid: Int32) -> Bool {
        guard sandbox.isRegularApp(pid: pid) else { return false }
        log.record("terminate", ["pid": pid])
        return true
    }
}

/// The real thing, for the tests that need a real window server, with every app and
/// PID checked first. Launch Services starts an app with launchd as its parent, so
/// the check goes by executable path rather than by descent from the test.
struct GuardedAppControl: AppControl {
    let sandbox: TestSandbox
    private let real = WorkspaceAppControl()

    func launch(appURL: URL, newInstance: Bool, arguments: [String], environment: [String: String]) async throws -> Int32 {
        try sandbox.requireInside(appURL.plainPath, what: "the app to launch")
        return try await real.launch(appURL: appURL, newInstance: newInstance, arguments: arguments, environment: environment)
    }

    @MainActor func activate(pid: Int32) -> Bool {
        sandbox.ownsExecutable(of: pid) && real.activate(pid: pid)
    }

    @MainActor func isRegularApp(pid: Int32) -> Bool {
        sandbox.ownsExecutable(of: pid) && real.isRegularApp(pid: pid)
    }

    @MainActor func terminate(pid: Int32) -> Bool {
        sandbox.ownsExecutable(of: pid) && real.terminate(pid: pid)
    }
}

/// `keychain.json` is a list of service names, so a test can seed a login without
/// a Keychain, and an unreadable list exercises the "unknown" state.
struct SeededCredentialProbe: CredentialProbe {
    let file: URL

    func state(forConfigDir configDir: URL, isDefault: Bool) -> CredentialState {
        guard let data = try? Data(contentsOf: file) else { return .absent }
        guard let services = try? JSONDecoder().decode([String].self, from: data) else { return .unknown }
        return services.contains(KeychainCredentialProbe.serviceName(forConfigDir: configDir, isDefault: isDefault)) ? .present : .absent
    }
}

struct FileDockPreferences: DockPreferences {
    private static let key = "persistent-apps"

    let file: URL
    let log: TestEventLog

    func persistentApps() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: file),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }
        return plist[Self.key] as? [[String: Any]] ?? []
    }

    func setPersistentApps(_ apps: [[String: Any]]) throws(HatsError) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: [Self.key: apps], format: .xml, options: 0).write(
                to: file, options: .atomic)
        } catch {
            throw HatsError(.io, "cannot save the test Dock preferences: \(error.localizedDescription)")
        }
        log.record("dock-write")
    }

    func restartDock() { log.record("dock-restart") }
}

struct RecordingFolderOpener: FolderOpener {
    let log: TestEventLog

    func open(_ folder: URL) -> Bool {
        log.record("reveal", ["path": folder.plainPath])
        return true
    }
}
#endif
