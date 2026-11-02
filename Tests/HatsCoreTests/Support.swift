import Foundation
@testable import HatsCore

/// A throwaway HOME, HATS_HOME and launcher dir per test.
struct Sandbox {
    let root: URL
    let layout: Layout
    let environment: [String: String]

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "hats-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        environment = [
            "HOME": home.plainPath,
            "HATS_HOME": root.appending(path: "hats-home").plainPath,
            "HATS_LAUNCHER_DIR": root.appending(path: "launchers").plainPath,
            "PATH": "/usr/bin:/bin",
        ]
        layout = Layout(environment: environment)
    }

    var store: ProfileStore { ProfileStore(layout: layout) }

    /// A Doctor that never consults the real Launch Services or Keychain.
    func doctor(
        processes: any ProcessTable = FakeProcessTable(),
        credentials: any CredentialProbe = FakeCredentialProbe(),
        claudeURLHandler: URL? = nil,
        install: HatsInstall? = nil
    ) -> Doctor {
        Doctor(
            layout: layout, processes: processes, credentials: credentials, environment: environment,
            urlSchemeHandler: { _ in claudeURLHandler }, install: install)
    }

    /// Never registers bundles with the real Launch Services database.
    var launchers: LauncherBuilder { LauncherBuilder(layout: layout, registrar: AppRegistrar { _ in }) }

    /// Moves discarded data into the sandbox instead of the real Trash.
    var discarder: Discarder {
        let trash = root.appending(path: "trash", directoryHint: .isDirectory)
        return Discarder { url in
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: trash.appending(path: UUID().uuidString))
        }
    }

    func makeDirectory(_ relativePath: String) throws -> URL {
        let url = root.appending(path: relativePath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeExecutable(_ relativePath: String) throws -> URL {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.plainPath)
        return url
    }

    func writeReceipt(_ contents: String) throws {
        try FileManager.default.createDirectory(at: layout.hatsHome, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: layout.installReceipt)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

final class FakeProcessTable: ProcessTable, @unchecked Sendable {
    var processes: [(summary: ProcessSummary, details: ProcessDetails?)] = []

    func summaries() -> [ProcessSummary] { processes.map(\.summary) }

    func details(of pid: Int32) -> ProcessDetails? {
        processes.first { $0.summary.pid == pid }?.details
    }

    func addDesktop(pid: Int32, userDataDir: String?, configDir: String?, start: Date = Date(timeIntervalSince1970: 1_000)) {
        var arguments = ["/Applications/Claude.app/Contents/MacOS/Claude"]
        if let userDataDir { arguments.append("--user-data-dir=\(userDataDir)") }
        processes.append(
            (
                ProcessSummary(pid: pid, parentPID: 1, startTime: start, command: "Claude"),
                ProcessDetails(
                    executablePath: "/Applications/Claude.app/Contents/MacOS/Claude",
                    arguments: arguments,
                    claudeConfigDir: configDir
                )
            ))
    }

    func addCLI(
        pid: Int32, parent: Int32 = 1, command: String = "2.1.312", configDir: String?, arguments: [String] = ["claude"],
        start: Date = Date(timeIntervalSince1970: 2_000)
    ) {
        processes.append(
            (
                ProcessSummary(pid: pid, parentPID: parent, startTime: start, command: command),
                ProcessDetails(
                    executablePath: "/Users/alice/.local/share/claude/versions/2.1.312",
                    arguments: arguments,
                    claudeConfigDir: configDir
                )
            ))
    }

    func addApp(pid: Int32, parent: Int32 = 1, command: String) {
        processes.append((ProcessSummary(pid: pid, parentPID: parent, startTime: Date(timeIntervalSince1970: 0), command: command), nil))
    }
}

final class FakeAppControl: AppControl, @unchecked Sendable {
    struct Launch: Equatable {
        let appURL: URL
        let newInstance: Bool
        let arguments: [String]
        let environment: [String: String]
    }

    var launches: [Launch] = []
    var activated: [Int32] = []
    var regularApps: Set<Int32> = []
    var nextPID: Int32 = 9_999

    func launch(appURL: URL, newInstance: Bool, arguments: [String], environment: [String: String]) async throws -> Int32 {
        launches.append(Launch(appURL: appURL, newInstance: newInstance, arguments: arguments, environment: environment))
        return nextPID
    }

    @MainActor func activate(pid: Int32) -> Bool {
        guard regularApps.contains(pid) else { return false }
        activated.append(pid)
        return true
    }

    @MainActor func isRegularApp(pid: Int32) -> Bool { regularApps.contains(pid) }

    var terminated: [Int32] = []

    @MainActor func terminate(pid: Int32) -> Bool {
        guard regularApps.contains(pid) else { return false }
        terminated.append(pid)
        return true
    }
}

final class FakeFolderOpener: FolderOpener, @unchecked Sendable {
    var opened: [URL] = []

    func open(_ folder: URL) -> Bool {
        opened.append(folder)
        return true
    }
}

final class FakeDockPreferences: DockPreferences, @unchecked Sendable {
    var apps: [[String: Any]] = []
    var restarts = 0
    var writes = 0

    func persistentApps() -> [[String: Any]] { apps }

    func setPersistentApps(_ apps: [[String: Any]]) throws(HatsError) {
        self.apps = apps
        writes += 1
    }

    func restartDock() { restarts += 1 }
}

final class FakeRegistrar: @unchecked Sendable {
    var registered: [String] = []

    var registrar: AppRegistrar { AppRegistrar { self.registered.append($0.plainPath) } }
}

struct FakeCredentialProbe: CredentialProbe {
    var present: Set<String> = []

    func state(forConfigDir configDir: URL, isDefault: Bool) -> CredentialState {
        present.contains(configDir.plainPath) ? .present : .absent
    }
}

func writeRegistryEntry(
    in configDir: URL, pid: Int32, procStart: String?, startedAt: Double? = 1_793_132_132_394, status: String = "idle",
    entrypoint: String = "cli", name: String = "s"
) throws {
    let dir = configDir.appending(path: "sessions", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var object: [String: Any] = [
        "pid": pid, "sessionId": "sid-\(pid)", "cwd": "/work/\(pid)",
        "entrypoint": entrypoint, "name": name, "status": status, "kind": "interactive", "futureField": ["x": 1],
    ]
    if let procStart { object["procStart"] = procStart }
    if let startedAt { object["startedAt"] = startedAt }
    try JSONSerialization.data(withJSONObject: object).write(to: dir.appending(path: "\(pid).json"))
}

func ctime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
    return formatter.string(from: date)
}
