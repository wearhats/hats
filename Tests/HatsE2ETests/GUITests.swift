import Foundation
import Testing

enum GUIGate {
    static let isEnabled = ProcessInfo.processInfo.environment["HATS_E2E_GUI"] == "1"
}

/// Real launches, activation and quits through hats' guarded `AppControl`, against a
/// stub app. Serialized because which app is frontmost is global.
@Suite("Real apps", .tags(.e2e, .gui), .serialized, .enabled(if: GUIGate.isEnabled))
struct GUITests {
    /// From `lsappinfo`, because `NSWorkspace` only updates this from a run loop, which
    /// a test process doesn't spin.
    private func frontmostPID() throws -> Int32? {
        let front = try CommandRunner.run(executable: "/usr/bin/lsappinfo", arguments: ["front"], environment: [:])
        let info = try CommandRunner.run(
            executable: "/usr/bin/lsappinfo",
            arguments: ["info", "-only", "pid", front.stdout.trimmingCharacters(in: .whitespacesAndNewlines)],
            environment: [:])
        return info.stdout.firstMatch(of: /pid"? *= *(\d+)/).flatMap { Int32($0.output.1) }
    }

    private func prepare() throws -> (sandbox: E2ESandbox, stub: StubApp, environment: [String: String]) {
        let sandbox = try E2ESandbox()
        sandbox.runsWithoutSeatbelt = true
        let stub = try StubApp(at: "\(sandbox.root)/apps/Claude.app", in: sandbox)
        return (sandbox, stub, ["HATS_TEST_APP_CONTROL": "guarded", "HATS_CLAUDE_APP": stub.path])
    }

    @Test func openLaunchesARealInstanceWithTheProfilesArgumentsAndEnvironment() throws {
        let (sandbox, stub, environment) = try prepare()
        defer { #expect(throws: Never.self) { try stub.stopEverything() } }
        let code = try sandbox.addProfile("work")

        let result = try sandbox.hats(["open", "work"], environment: environment)

        #expect(result.exit == 0, "\(result)")
        let report = try waitUntil("the launched stub to report") { try stub.reports().first }
        #expect(report.arguments == ["--user-data-dir=\(sandbox.profileDir("work"))/desktop"])
        #expect(report.configDir == code)
        #expect(result.stdout == "Launched Claude (Work), pid \(report.pid).\n", "\(result)")
    }

    @Test func aSecondOpenFocusesAndStartsNothingNew() throws {
        let (sandbox, stub, environment) = try prepare()
        defer { #expect(throws: Never.self) { try stub.stopEverything() } }
        try sandbox.addProfile("work")
        #expect(try sandbox.hats(["open", "work"], environment: environment).exit == 0)
        let report = try waitUntil("the launched stub to report") { try stub.reports().first }

        let result = try sandbox.hats(["open", "work"], environment: environment)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "Focused Claude (Work), pid \(report.pid).\n", "\(result)")
        #expect(try stub.reports().count == 1)
    }

    /// Puts the other app in front first, so this can't pass with focus doing nothing.
    @Test func focusReallyBringsTheAppForward() throws {
        let (sandbox, stub, environment) = try prepare()
        defer { #expect(throws: Never.self) { try stub.stopEverything() } }
        try sandbox.addProfile("work")
        try sandbox.addProfile("other")
        let base = sandbox.processEnvironment([:], removing: [])
        let work = try stub.startDirectly(arguments: ["--user-data-dir=\(sandbox.profileDir("work"))/desktop"], environment: base)
        let other = try stub.startDirectly(arguments: ["--user-data-dir=\(sandbox.profileDir("other"))/desktop"], environment: base)
        func waitForFrontmost(_ pid: Int32) throws {
            _ = try waitUntil("pid \(pid) to be frontmost") {
                try frontmostPID() == pid ? true : nil
            }
        }
        #expect(try sandbox.hats(["focus", String(other)], environment: environment).exit == 0)
        try waitForFrontmost(other)

        let result = try sandbox.hats(["focus", String(work)], environment: environment)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "Focused pid \(work) hosting desktop pid \(work).\n", "\(result)")
        try waitForFrontmost(work)
    }

    @Test func dedupeReallyQuitsTheNewerAndKeepsTheOlder() throws {
        let (sandbox, stub, environment) = try prepare()
        defer { #expect(throws: Never.self) { try stub.stopEverything() } }
        try sandbox.addProfile("work")
        let base = sandbox.processEnvironment([:], removing: [])
        let arguments = ["--user-data-dir=\(sandbox.profileDir("work"))/desktop"]
        let older = try stub.startDirectly(arguments: arguments, environment: base)
        let newer = try stub.startDirectly(arguments: arguments, environment: base)

        let result = try sandbox.hats(["dedupe", "--yes"], environment: environment)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("'work': keep pid \(older), quit \(newer)"), "\(result)")
        _ = try waitUntil("pid \(newer) to quit") { stub.isRunning(newer) ? nil : true }
        #expect(stub.isRunning(older))
    }
}
