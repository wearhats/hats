import Foundation
import Testing

@Suite("hats ps", .tags(.e2e))
struct ProcessListTests {
    private let instanceKeys: Set<String> = [
        "profile", "kind", "pid", "startedAt", "status", "name", "cwd", "sessionId", "version", "dataDir", "configDir",
    ]

    private func instances(_ sandbox: E2ESandbox, _ arguments: [String] = []) throws -> [[String: Any]] {
        let result = try sandbox.hats(["ps", "--json"] + arguments)
        #expect(result.exit == 0, "\(result)")
        return try sandbox.json(result)
    }

    private func instance(_ fake: FakeProcess, in rows: [[String: Any]]) -> [String: Any]? {
        rows.first { $0["pid"] as? Int == Int(fake.pid) }
    }

    @Test func withNothingRunningItSaysSo() throws {
        let result = try E2ESandbox().hats(["ps"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "No running Claude instances.\n", "\(result)")
    }

    /// The positive and negative control for test mode: the same fake is seen by
    /// the sandbox it runs in, and not by any other.
    @Test func aProcessIsVisibleOnlyToTheSandboxItRunsIn() throws {
        let inside = try E2ESandbox()
        let other = try E2ESandbox()
        let fake = try inside.startCLI(configDir: try inside.addProfile("work"))
        _ = try other.addProfile("work")

        #expect(instance(fake, in: try instances(inside)) != nil)
        #expect(instance(fake, in: try instances(other)) == nil)
    }

    @Test func aRegisteredSessionShowsItsNameStatusAndDirectory() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        let fake = try sandbox.startCLI(
            configDir: code,
            session: #"{"name":"fix-bug","status":"busy","entrypoint":"cli","cwd":"/work/repo","sessionId":"sid-1","version":"2.1.999"}"#)

        let table = try sandbox.hats(["ps"])
        let row = try #require(instance(fake, in: try instances(sandbox)))

        #expect(row["profile"] as? String == "work")
        #expect(row["kind"] as? String == "cli")
        #expect(row["name"] as? String == "fix-bug")
        #expect(row["status"] as? String == "busy")
        #expect(row["cwd"] as? String == "/work/repo")
        #expect(row["sessionId"] as? String == "sid-1")
        #expect(row["version"] as? String == "2.1.999")
        let line = try #require(table.stdout.split(separator: "\n").first { $0.contains(String(fake.pid)) }, "\(table)")
        #expect(line.hasPrefix("work"), "\(table)")
        #expect(line.contains("fix-bug") && line.contains("busy") && line.contains("/work/repo"), "\(table)")
    }

    @Test func anUnregisteredSessionShowsDashes() throws {
        let sandbox = try E2ESandbox()
        let fake = try sandbox.startCLI(configDir: try sandbox.addProfile("work"))

        let row = try #require(instance(fake, in: try instances(sandbox)))
        let table = try sandbox.hats(["ps"])

        #expect(row["name"] is NSNull)
        #expect(row["status"] is NSNull)
        #expect(table.stdout.split(separator: "\n").contains { $0.contains(String(fake.pid)) && $0.hasSuffix("-") }, "\(table)")
    }

    @Test func aDeadSessionIsDropped() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        let fake = try sandbox.startCLI(configDir: code, session: #"{"name":"gone"}"#)
        #expect(sandbox.exists("\(code)/sessions/\(fake.pid).json"))
        fake.stop()

        #expect(try instances(sandbox).isEmpty)
    }

    /// Registry files outlive their process and macOS reuses PIDs.
    @Test func anEntryForAPIDReusedByAnotherProgramIsDropped() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        let other = try sandbox.startFake(at: "bin/helper")
        try sandbox.write(
            #"{"pid":\#(other.pid),"name":"stale","startedAt":\#(Date.now.timeIntervalSince1970 * 1_000)}"#,
            to: "\(code)/sessions/\(other.pid).json")

        #expect(try instances(sandbox).isEmpty)
    }

    @Test func aMismatchedStartTimeFallsBackToUnregistered() throws {
        let sandbox = try E2ESandbox()
        let fake = try sandbox.startCLI(
            configDir: try sandbox.addProfile("work"), session: #"{"name":"stale"}"#, timestamps: "startedAt", stale: 3_600)

        let row = try #require(instance(fake, in: try instances(sandbox)))

        #expect(row["name"] is NSNull)
    }

    /// The real kernel start time against the real format, which only synthetic
    /// dates have exercised elsewhere.
    @Test func procStartAloneIsEnough() throws {
        let sandbox = try E2ESandbox()
        let fake = try sandbox.startCLI(
            configDir: try sandbox.addProfile("work"), session: #"{"name":"by-proc-start"}"#, timestamps: "procStart")

        #expect(instance(fake, in: try instances(sandbox))?["name"] as? String == "by-proc-start")
    }

    @Test func aMismatchedProcStartFallsBackToUnregistered() throws {
        let sandbox = try E2ESandbox()
        let fake = try sandbox.startCLI(
            configDir: try sandbox.addProfile("work"), session: #"{"name":"stale"}"#, timestamps: "procStart", stale: 3_600)

        #expect(try #require(instance(fake, in: try instances(sandbox)))["name"] is NSNull)
    }

    @Test func noTimestampMeansUnregistered() throws {
        let sandbox = try E2ESandbox()
        let fake = try sandbox.startCLI(configDir: try sandbox.addProfile("work"), session: #"{"name":"unknown"}"#, timestamps: "none")

        #expect(try #require(instance(fake, in: try instances(sandbox)))["name"] is NSNull)
    }

    /// The native installer runs `.../claude/versions/<version>`, so the kernel name
    /// is the version string.
    @Test func aNativeInstallIsRecognized() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        let fake = try sandbox.startFake(at: "local/claude/versions/2.1.999", environment: ["CLAUDE_CONFIG_DIR": code])

        #expect(instance(fake, in: try instances(sandbox))?["profile"] as? String == "work")
    }

    @Test func noConfigDirMeansDefault() throws {
        let sandbox = try E2ESandbox()
        let fake = try sandbox.startCLI(configDir: nil, session: #"{"name":"stock"}"#)

        let row = try #require(instance(fake, in: try instances(sandbox)))

        #expect(row["profile"] as? String == "default")
        #expect(row["name"] as? String == "stock")
    }

    @Test func anUnmanagedDirShowsInParentheses() throws {
        let sandbox = try E2ESandbox()
        let unmanaged = "\(sandbox.home)/.claude-mine"
        try sandbox.makeDirectory(unmanaged)
        let fake = try sandbox.startCLI(configDir: unmanaged, session: #"{"name":"in-unmanaged"}"#)

        let row = try #require(instance(fake, in: try instances(sandbox)))
        let table = try sandbox.hats(["ps"])

        #expect(row["profile"] is NSNull)
        #expect(row["dataDir"] as? String == sandbox.reported(unmanaged))
        #expect(row["name"] as? String == "in-unmanaged")
        #expect(table.stdout.contains("(\(sandbox.reported(unmanaged)))"), "\(table)")
    }

    @Test func theTableShortensPathsAgainstThisHome() throws {
        let sandbox = try E2ESandbox()
        let fake = try sandbox.startCLI(
            configDir: try sandbox.addProfile("work"), session: #"{"cwd":"\#(sandbox.home)/repo","name":"at-home"}"#)

        let result = try sandbox.hats(["ps"])

        let line = try #require(result.stdout.split(separator: "\n").first { $0.contains(String(fake.pid)) }, "\(result)")
        #expect(line.hasSuffix("~/repo"), "\(result)")
    }

    @Test func aDesktopIsAttributedByItsDataDir() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let fake = try sandbox.startDesktop(profile: "work")

        let row = try #require(instance(fake, in: try instances(sandbox)))

        #expect(row["profile"] as? String == "work")
        #expect(row["kind"] as? String == "desktop")
        #expect(row["dataDir"] as? String == sandbox.reported("\(sandbox.profileDir("work"))/desktop"))
        #expect(row["configDir"] as? String == "\(sandbox.profileDir("work"))/code")
    }

    @Test func aDesktopWithNoDataDirIsDefault() throws {
        let sandbox = try E2ESandbox()
        let fake = try sandbox.startDesktop()

        #expect(instance(fake, in: try instances(sandbox))?["profile"] as? String == "default")
    }

    @Test func helpersAreIgnored() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        let renderer = try sandbox.startDesktop(profile: "work", arguments: ["--type=renderer"])
        let mcp = try sandbox.startCLI(configDir: code, arguments: ["mcp"])
        let version = try sandbox.startCLI(configDir: code, arguments: ["--version"])
        let session = try sandbox.startCLI(configDir: code)

        let rows = try instances(sandbox)

        #expect(instance(session, in: rows) != nil)
        #expect(instance(renderer, in: rows) == nil)
        #expect(instance(mcp, in: rows) == nil)
        #expect(instance(version, in: rows) == nil)
    }

    @Test func profileFilters() throws {
        let sandbox = try E2ESandbox()
        let work = try sandbox.startCLI(configDir: try sandbox.addProfile("work"))
        let other = try sandbox.startCLI(configDir: try sandbox.addProfile("other"))

        let rows = try instances(sandbox, ["--profile", "work"])

        #expect(instance(work, in: rows) != nil)
        #expect(instance(other, in: rows) == nil)
    }

    @Test func jsonHasEveryKeyAndAnISO8601Start() throws {
        let sandbox = try E2ESandbox()
        let cli = try sandbox.startCLI(configDir: try sandbox.addProfile("work"))
        let desktop = try sandbox.startDesktop(profile: "work")

        let rows = try instances(sandbox)

        for fake in [cli, desktop] {
            let row = try #require(instance(fake, in: rows))
            #expect(Set(row.keys) == instanceKeys, "\(row)")
            let startedAt = try #require(row["startedAt"] as? String)
            #expect(ISO8601DateFormatter().date(from: startedAt) != nil, "\(startedAt)")
        }
    }

    @Test func anUndecodableRegistryFileDoesNotFailTheCommand() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        try sandbox.write("{ not json", to: "\(code)/sessions/1.json")
        let fake = try sandbox.startCLI(configDir: code)

        #expect(instance(fake, in: try instances(sandbox)) != nil)
    }

    /// The API key sits in the fake's real environment block, and the sentinel check
    /// in `hats()` fails if it reaches any output. This proves the block was read.
    @Test func ofAProcessEnvironmentOnlyTheConfigDirIsKept() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        let fake = try sandbox.startCLI(configDir: code)

        let result = try sandbox.hats(["ps", "--json"])

        #expect(instance(fake, in: try sandbox.json(result))?["dataDir"] as? String == sandbox.reported(code))
    }
}

@Suite("hats focus", .tags(.e2e))
struct FocusCommandTests {
    @Test func noMatchFailsWithAHint() throws {
        let result = try E2ESandbox().hats(["focus", "nothing"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr == "hats: no running instance matches 'nothing'\nhint: see: hats ps\n", "\(result)")
    }

    @Test func aNameMatchingTwoSessionsIsAUsageError() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        _ = try sandbox.startCLI(configDir: code, session: #"{"name":"twin"}"#)
        _ = try sandbox.startCLI(configDir: code, session: #"{"name":"twin"}"#)

        let result = try sandbox.hats(["focus", "twin"])

        #expect(result.exit == 64, "\(result)")
        #expect(result.stderr.contains("matches 2 instances"), "\(result)")
    }

    @Test(arguments: ["pid", "name", "session"])
    func findsASessionByEachIdentifierAndFocusesItsHost(identifier: String) throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        let host = try sandbox.startFake(
            at: "apps/Terminal.app/Contents/MacOS/Terminal",
            environment: [
                "HATS_FAKE_SPAWN": try sandbox.installFake(at: "bin/claude"), "CLAUDE_CONFIG_DIR": code,
                "HATS_FAKE_SESSION": #"{"name":"fix-bug","sessionId":"sid-1"}"#,
            ],
            readyLines: 2)
        let session = try #require(host.childPID)
        let terminal = host.pid
        let target = identifier == "pid" ? String(session) : identifier == "name" ? "fix-bug" : "sid-1"

        let result = try sandbox.hats(["focus", target])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "Focused pid \(terminal) hosting cli pid \(session).\n", "\(result)")
        #expect(try sandbox.events("activate").map { $0["pid"] as? Int } == [Int(terminal)])
    }

    @Test func aDesktopIsItsOwnHost() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let fake = try sandbox.startDesktop(profile: "work")

        let result = try sandbox.hats(["focus", String(fake.pid)])

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.events("activate").map { $0["pid"] as? Int } == [Int(fake.pid)])
    }

    @Test func noRegularAppInTheChainFails() throws {
        let sandbox = try E2ESandbox()
        let fake = try sandbox.startCLI(configDir: try sandbox.addProfile("work"))

        let result = try sandbox.hats(["focus", String(fake.pid)])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("cannot find a window for pid \(fake.pid)"), "\(result)")
        #expect(try sandbox.events("activate").isEmpty)
    }
}

@Suite("hats dedupe", .tags(.e2e))
struct DedupeCommandTests {
    private func duplicates(_ sandbox: E2ESandbox) throws -> (older: FakeProcess, newer: FakeProcess) {
        try sandbox.addProfile("work")
        let older = try sandbox.startDesktop(profile: "work")
        return (older, try sandbox.startDesktop(profile: "work"))
    }

    @Test func withNoDuplicatesItSaysSo() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        _ = try sandbox.startDesktop(profile: "work")

        let result = try sandbox.hats(["dedupe", "--yes"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "No duplicate Claude Desktop instances.\n", "\(result)")
        #expect(try sandbox.events("terminate").isEmpty)
    }

    @Test func dryRunNamesTheOlderAsKeepAndRecordsNothing() throws {
        let sandbox = try E2ESandbox()
        let (older, newer) = try duplicates(sandbox)

        let result = try sandbox.hats(["dedupe", "--dry-run"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "'work': keep pid \(older.pid), quit \(newer.pid)\n", "\(result)")
        #expect(try sandbox.events().isEmpty)
    }

    @Test func withoutATerminalItNeedsYes() throws {
        let sandbox = try E2ESandbox()
        _ = try duplicates(sandbox)

        let result = try sandbox.hats(["dedupe"])

        #expect(result.exit == 64, "\(result)")
        #expect(try sandbox.events("terminate").isEmpty)
    }

    @Test func yesAsksOnlyTheNewerToQuit() throws {
        let sandbox = try E2ESandbox()
        let (_, newer) = try duplicates(sandbox)

        let result = try sandbox.hats(["dedupe", "--yes"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("Asked 1 instance(s) to quit."), "\(result)")
        #expect(try sandbox.events("terminate").map { $0["pid"] as? Int } == [Int(newer.pid)])
    }

    @Test func anUnmanagedDirIsNamedByItsPath() throws {
        let sandbox = try E2ESandbox()
        let dir = "\(sandbox.root)/unmanaged-data"
        try sandbox.makeDirectory(dir)
        let older = try sandbox.startDesktop(userDataDir: dir)
        let newer = try sandbox.startDesktop(userDataDir: dir)

        let result = try sandbox.hats(["dedupe", "--dry-run"])

        #expect(result.stdout == "\(sandbox.reported(dir)): keep pid \(older.pid), quit \(newer.pid)\n", "\(result)")
    }

    @Test func aDefaultDuplicatePrintsTheReopenHint() throws {
        let sandbox = try E2ESandbox()
        _ = try sandbox.startDesktop()
        _ = try sandbox.startDesktop()

        let result = try sandbox.hats(["dedupe", "--yes"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("reopen your profiles with: hats open --all"), "\(result)")
    }

    /// Outside a `.app` the stand-in refuses, as a real app can refuse to quit.
    @Test func aRefusalFails() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        _ = try sandbox.startFake(
            at: "bare/Contents/MacOS/Claude", arguments: ["--user-data-dir=\(sandbox.profileDir("work"))/desktop"])
        let newer = try sandbox.startFake(
            at: "bare/Contents/MacOS/Claude", arguments: ["--user-data-dir=\(sandbox.profileDir("work"))/desktop"])

        let result = try sandbox.hats(["dedupe", "--yes"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("could not quit pids \(newer.pid)"), "\(result)")
    }
}

@Suite("Commands that care what is running", .tags(.e2e))
struct RunningProfileTests {
    @Test func openFocusesARunningInstanceInsteadOfLaunching() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let fake = try sandbox.startDesktop(profile: "work")

        let result = try sandbox.hats(["open", "work"], environment: try sandbox.withClaudeApp)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "Focused Claude (Work), pid \(fake.pid).\n", "\(result)")
        #expect(try sandbox.events("activate").map { $0["pid"] as? Int } == [Int(fake.pid)])
        #expect(try sandbox.events("launch").isEmpty)
    }

    @Test func openRefusesAnInstanceItCannotBringForward() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let fake = try sandbox.startFake(
            at: "bare/Contents/MacOS/Claude", arguments: ["--user-data-dir=\(sandbox.profileDir("work"))/desktop"])

        let result = try sandbox.hats(["open", "work"], environment: try sandbox.withClaudeApp)

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("is running (pid \(fake.pid)) and could not be brought forward"), "\(result)")
        #expect(try sandbox.events("launch").isEmpty)
    }

    @Test func lsCountsRunningInstances() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        _ = try sandbox.startDesktop(profile: "work")
        _ = try sandbox.startCLI(configDir: code)

        let rows = try sandbox.json(try sandbox.hats(["ls", "--json"]))

        let row = try #require(rows.first { $0["name"] as? String == "work" })
        #expect(row["runningDesktop"] as? Int == 1)
        #expect(row["runningSessions"] as? Int == 1)
    }

    @Test(arguments: [
        ["reset", "work", "--yes"], ["reset", "work", "--dry-run"], ["rm", "work"], ["rm", "work", "--purge", "--yes"],
        ["rm", "work", "--purge", "--force", "--yes"],
    ])
    func aRunningProfileIsRefused(arguments: [String]) throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        let fake = try sandbox.startDesktop(profile: "work")
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(arguments)

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("pids \(fake.pid)"), "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
        #expect(try sandbox.trashed().isEmpty)
    }

    @Test func forceRemovesOnlyTheLauncherOfARunningProfile() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        _ = try sandbox.startDesktop(profile: "work")
        let launcherPrefix = "launchers/"
        let before = try sandbox.snapshot().filter { !$0.key.hasPrefix(launcherPrefix) }

        let result = try sandbox.hats(["rm", "work", "--force"])

        #expect(result.exit == 0, "\(result)")
        #expect(!sandbox.exists(sandbox.launcher("Work")))
        #expect(try sandbox.snapshot().filter { !$0.key.hasPrefix(launcherPrefix) } == before, "\(result)")
        #expect(try sandbox.trashed().isEmpty)
    }
}

@Suite("hats doctor on running instances", .tags(.e2e))
struct DoctorInstanceTests {
    private func findings(_ sandbox: E2ESandbox, sourceLocation: SourceLocation = #_sourceLocation) throws -> (
        result: CommandResult, findings: [[String: Any]]
    ) {
        try sandbox.doctor(environment: try sandbox.withClaudeApp, sourceLocation: sourceLocation)
    }

    private func hasInstanceFinding(_ findings: [[String: Any]], level: String, containing text: String) -> Bool {
        hasFinding(findings, level: level, check: "instances", containing: text)
    }

    @Test func aHealthyInstanceIsCounted() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        _ = try sandbox.startDesktop(profile: "work")

        let (_, found) = try findings(sandbox)

        #expect(hasInstanceFinding(found, level: "ok", containing: "1 Desktop and 0 Claude Code instances"), "\(found)")
    }

    @Test func duplicatesWarn() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        _ = try sandbox.startDesktop(profile: "work")
        _ = try sandbox.startDesktop(profile: "work")

        let (result, found) = try findings(sandbox)

        #expect(result.exit == 0, "\(result)")
        #expect(hasInstanceFinding(found, level: "warn", containing: "2 Desktop instances share profile 'work'"), "\(found)")
    }

    @Test(arguments: [nil, "/another-dir"] as [String?])
    func aProfileDesktopWithoutItsConfigDirFails(configDir: String?) throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        _ = try sandbox.startDesktop(profile: "work", configDir: .some(configDir.map { sandbox.root + $0 }))

        let (result, found) = try findings(sandbox)

        #expect(result.exit == 1, "\(result)")
        #expect(hasInstanceFinding(found, level: "fail", containing: "runs without its CLAUDE_CONFIG_DIR"), "\(found)")
    }

    @Test func anUnmanagedConfigDirWarnsWithTheAdoptHint() throws {
        let sandbox = try E2ESandbox()
        let dir = "\(sandbox.home)/.claude-mine"
        try sandbox.makeDirectory(dir)
        _ = try sandbox.startCLI(configDir: dir)

        let (_, found) = try findings(sandbox)

        let finding = try #require(
            found.first { ($0["message"] as? String)?.contains("unmanaged config dir \(sandbox.reported(dir))") == true }, "\(found)")
        #expect(finding["hint"] as? String == "adopt it with: hats add mine --code-dir \(sandbox.reported(dir))")
    }

    @Test func aBadRegistryFileWarns() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        try sandbox.write("{ not json", to: "\(code)/sessions/1.json")

        let (_, found) = try findings(sandbox)

        #expect(hasInstanceFinding(found, level: "warn", containing: "session files could not be read"), "\(found)")
    }
}
