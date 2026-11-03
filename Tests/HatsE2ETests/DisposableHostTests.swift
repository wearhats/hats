import Foundation
import Testing

/// These change the account's real Dock, Trash and Launch Services database, with no
/// test mode. Asking for them anywhere but a throwaway runner is a failure rather
/// than a skip, so a misconfigured job can't look green.
enum DisposableHost {
    static let isRequested = ProcessInfo.processInfo.environment["HATS_E2E_DISPOSABLE_HOST"] == "1"

    struct Refused: Error, CustomStringConvertible {
        var description: String { "HATS_E2E_DISPOSABLE_HOST is set, but this isn't a GitHub-hosted runner" }
    }

    static func requireThrowawayMachine(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_ENVIRONMENT"] == "github-hosted" else { throw Refused() }
    }
}

@Suite("The real Dock, Trash and Launch Services", .tags(.e2e, .disposableHost), .serialized, .enabled(if: DisposableHost.isRequested))
struct DisposableHostTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false).trimmingCharacters(
        in: CharacterSet(charactersIn: "/"))

    private var realHome: String { "/" + home }

    /// The account's real environment, on purpose: no sandbox, no test mode.
    private var environment: [String: String] {
        ["HOME": realHome, "PATH": "/usr/bin:/bin", "NO_COLOR": "1", "HATS_NO_UPDATE_CHECK": "1", "TMPDIR": NSTemporaryDirectory()]
    }

    private func hats(_ arguments: [String]) throws -> CommandResult {
        try CommandRunner.run(executable: try HatsBinary.path(), arguments: arguments, environment: environment, timeoutSeconds: 30)
    }

    private func dockPID() throws -> String? {
        let result = try CommandRunner.run(executable: "/usr/bin/pgrep", arguments: ["-x", "Dock"], environment: [:])
        return result.exit == 0 ? result.stdout : nil
    }

    private func dockPreferences() throws -> String {
        try CommandRunner.run(executable: "/usr/bin/defaults", arguments: ["read", "com.apple.dock", "persistent-apps"], environment: [:])
            .stdout
    }

    private func trashEntries(named name: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: "\(realHome)/.Trash").filter { $0.hasPrefix(name) }
    }

    @Test func pinAndUnpinChangeTheRealDockAndRestartIt() throws {
        try DisposableHost.requireThrowawayMachine()
        #expect(try hats(["add", "t2b-dock", "--label", "T2bDock"]).exit == 0)
        defer { _ = try? hats(["rm", "t2b-dock", "--purge", "--yes"]) }
        let restartedFrom = try dockPID()

        let pin = try hats(["dock", "pin", "t2b-dock"])

        #expect(pin.exit == 0, "\(pin)")
        _ = try waitUntil("the Dock to restart") {
            let current = try dockPID()
            return current != nil && current != restartedFrom ? true : nil
        }
        // A new Dock writes its list back once it has loaded, with no signal for when.
        // A tile it skipped or a cache that won would be gone by then. Whether it's
        // drawn takes a person: the release checklist has that.
        sleep(3)
        #expect(try dockPreferences().contains("Claude%20(T2bDock).app"))

        let again = try hats(["dock", "pin", "t2b-dock"])
        #expect(again.stdout.contains("is already in the Dock"), "\(again)")

        let unpin = try hats(["dock", "unpin", "t2b-dock"])

        #expect(unpin.exit == 0, "\(unpin)")
        _ = try waitUntil("the tile to go") { try dockPreferences().contains("Claude%20(T2bDock).app") ? nil : true }
    }

    @Test func resetAndPurgeUseTheRealTrash() throws {
        try DisposableHost.requireThrowawayMachine()
        #expect(try hats(["add", "t2b-trash"]).exit == 0)
        let dataDir = "\(realHome)/Library/Application Support/hats/profiles/t2b-trash"
        let desktopsBefore = try trashEntries(named: "desktop").count

        let reset = try hats(["reset", "t2b-trash", "--yes"])

        #expect(reset.exit == 0, "\(reset)")
        #expect(try trashEntries(named: "desktop").count == desktopsBefore + 1)
        #expect(FileManager.default.fileExists(atPath: "\(dataDir)/desktop"))

        let purge = try hats(["rm", "t2b-trash", "--purge", "--yes"])

        #expect(purge.exit == 0, "\(purge)")
        #expect(!FileManager.default.fileExists(atPath: dataDir))
        #expect(try !trashEntries(named: "t2b-trash").isEmpty)
    }

    /// Launch Services really starts the launcher, from launchd's environment, and it
    /// has to find Claude.app the way it would on a user's Mac: `~/Applications` is one
    /// of the places hats looks. The stub there keeps its own bundle ID.
    @Test func openingALauncherReachesClaude() throws {
        try DisposableHost.requireThrowawayMachine()
        let applications = "\(realHome)/Applications"
        try FileManager.default.createDirectory(atPath: applications, withIntermediateDirectories: true)
        let stub = try StubApp(at: "\(applications)/Claude.app")
        // In this order, because `rm --purge` refuses a profile that is still running.
        defer {
            #expect(throws: Never.self) { try stub.stopEverything() }
            try? FileManager.default.removeItem(atPath: stub.path)
            _ = try? hats(["rm", "t2b-click", "--purge", "--yes"])
        }
        let add = try hats(["add", "t2b-click", "--label", "T2bClick"])
        #expect(add.exit == 0, "\(add)")

        let click = try CommandRunner.run(
            executable: "/usr/bin/open", arguments: ["\(applications)/Hats/Claude (T2bClick).app"], environment: environment)

        #expect(click.exit == 0, "\(click)")
        let report = try waitUntil("the launcher to start Claude", timeoutSeconds: 30) { try stub.reports().first }
        let profile = "\(realHome)/Library/Application Support/hats/profiles/t2b-click"
        #expect(report.arguments == ["--user-data-dir=\(profile)/desktop"])
        #expect(report.configDir == "\(profile)/code")
    }
}
