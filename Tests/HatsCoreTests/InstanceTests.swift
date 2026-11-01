import Foundation
import Testing
@testable import HatsCore

@Suite struct SessionRegistryTests {
    @Test func decodesRealFixtureTolerantly() throws {
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let data = try Data(contentsOf: fixtures.appending(path: "claude-code/2.1.312/sessions-interactive.json"))
        let session = try JSONDecoder().decode(RegisteredSession.self, from: data)
        #expect(session.pid == 22045)
        #expect(session.status == "waiting")
        #expect(session.entrypoint == "cli")
        #expect(session.startedAtDate == Date(timeIntervalSince1970: 1_793_132_132.394))
    }

    @Test func skipsAndCountsUndecodableFiles() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let code = try sandbox.makeDirectory("code")
        try writeRegistryEntry(in: code, pid: 10, procStart: nil)
        let sessions = code.appending(path: "sessions")
        try Data("not json".utf8).write(to: sessions.appending(path: "11.json"))
        try Data("{}".utf8).write(to: sessions.appending(path: "notes.json"))
        try Data("secret".utf8).write(to: sessions.appending(path: "10.abc.key"))
        let reading = SessionRegistry.read(configDir: code)
        #expect(reading.sessions.map(\.pid) == [10])
        #expect(reading.undecodableFiles.count == 1)
    }

    @Test func procStartComparisonNormalizesCtimePadding() throws {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (
            2026, 10, 7, 20, 15, 31
        )
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try #require(calendar.date(from: components))
        #expect(SessionRegistry.procStartMatches("Wed Oct  7 20:15:31 2026", startTime: date, timeZone: utc))
        #expect(!SessionRegistry.procStartMatches("Wed Oct  7 20:15:32 2026", startTime: date, timeZone: utc))
    }
}

@Suite struct InstanceScannerTests {
    @Test func attributesDesktopInstancesByExactDataDir() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        try sandbox.store.create(ProfileName("work2"))
        let table = FakeProcessTable()
        table.addDesktop(pid: 100, userDataDir: nil, configDir: nil)
        table.addDesktop(pid: 101, userDataDir: work.desktopDir.plainPath, configDir: work.codeDir.plainPath)
        table.addDesktop(pid: 102, userDataDir: "/elsewhere", configDir: nil)

        let instances = InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances
        #expect(instances.map(\.pid) == [100, 101, 102])
        #expect(instances.map(\.profile?.rawValue) == ["default", "work", nil])
        #expect(instances[1].configDir == work.codeDir.plainPath)
    }

    @Test func ignoresElectronHelpers() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let table = FakeProcessTable()
        table.processes.append(
            (
                ProcessSummary(pid: 5, parentPID: 1, startTime: Date(), command: "Claude"),
                ProcessDetails(
                    executablePath: "/Applications/Claude.app/Contents/MacOS/Claude", arguments: ["Claude", "--type=renderer"],
                    claudeConfigDir: nil)
            ))
        #expect(InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances.isEmpty)
    }

    @Test func joinsRegistryWithLiveProcessesAndDropsStaleEntries() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let start = Date(timeIntervalSince1970: 1_793_132_131)
        let table = FakeProcessTable()
        table.addCLI(pid: 200, configDir: work.codeDir.plainPath, start: start)
        table.addCLI(pid: 201, configDir: work.codeDir.plainPath, start: start)
        try writeRegistryEntry(in: work.codeDir, pid: 200, procStart: ctime(start), status: "waiting", name: "api")
        try writeRegistryEntry(in: work.codeDir, pid: 201, procStart: "Mon Jan  1 00:00:00 2001", startedAt: 978_307_200_000)
        try writeRegistryEntry(in: work.codeDir, pid: 299, procStart: nil)

        let instances = InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances
        let registered = try #require(instances.first { $0.pid == 200 })
        #expect(registered.status == "waiting")
        #expect(registered.name == "api")
        #expect(registered.profile?.rawValue == "work")
        let reusedPID = try #require(instances.first { $0.pid == 201 })
        #expect(reusedPID.status == nil)
        #expect(!instances.contains { $0.pid == 299 })
    }

    @Test func entriesWithoutProcStartAreValidatedByStartedAt() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let table = FakeProcessTable()
        table.addCLI(pid: 500, configDir: work.codeDir.plainPath, start: Date(timeIntervalSince1970: 1_793_132_131))
        table.addCLI(pid: 501, configDir: work.codeDir.plainPath, start: Date(timeIntervalSince1970: 1_793_000_000))
        for pid: Int32 in [500, 501] { try writeRegistryEntry(in: work.codeDir, pid: pid, procStart: nil, status: "busy") }

        let instances = InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances
        #expect(instances.first { $0.pid == 500 }?.status == "busy")
        #expect(instances.first { $0.pid == 501 }?.status == nil)
    }

    @Test func entriesWithNeitherTimestampAreDropped() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let table = FakeProcessTable()
        table.addCLI(pid: 510, configDir: work.codeDir.plainPath)
        try writeRegistryEntry(in: work.codeDir, pid: 510, procStart: nil, startedAt: nil, status: "busy")
        let instances = InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances
        #expect(instances.first { $0.pid == 510 }?.status == nil)
    }

    @Test func aReusedPIDThatIsNotClaudeIsNeverShown() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let table = FakeProcessTable()
        let start = Date(timeIntervalSince1970: 1_793_132_131)
        table.processes.append(
            (
                ProcessSummary(pid: 520, parentPID: 1, startTime: start, command: "Safari"),
                ProcessDetails(
                    executablePath: "/Applications/Safari.app/Contents/MacOS/Safari", arguments: ["Safari"], claudeConfigDir: nil)
            ))
        try writeRegistryEntry(in: work.codeDir, pid: 520, procStart: ctime(start))
        #expect(InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances.isEmpty)
    }

    @Test func startedAtWinsOverAProcStartFromAnotherTimeZone() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let start = Date(timeIntervalSince1970: 1_793_132_131)
        let table = FakeProcessTable()
        table.addCLI(pid: 530, configDir: work.codeDir.plainPath, start: start)
        try writeRegistryEntry(in: work.codeDir, pid: 530, procStart: ctime(start.addingTimeInterval(3_600)), status: "busy")
        let instances = InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances
        #expect(instances.first { $0.pid == 530 }?.status == "busy")
    }

    @Test func readsRegistriesOfUnmanagedConfigDirs() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let unmanaged = try sandbox.makeDirectory("home/.claude-work")
        let table = FakeProcessTable()
        table.addCLI(pid: 300, configDir: unmanaged.plainPath, start: Date(timeIntervalSince1970: 1_793_132_131))
        try writeRegistryEntry(in: unmanaged, pid: 300, procStart: nil, status: "busy")

        let instance = try #require(InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances.first)
        #expect(instance.profile == nil)
        #expect(instance.dataDir == unmanaged.canonicalPath)
        #expect(instance.status == "busy")
    }

    @Test func recognisesNativeInstallAndSkipsHelpers() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let table = FakeProcessTable()
        table.addCLI(pid: 400, command: "2.1.312", configDir: nil)
        table.addCLI(pid: 401, command: "claude", configDir: nil, arguments: ["claude", "--chrome-native-host"])
        table.addCLI(pid: 402, command: "node", configDir: nil, arguments: ["node", "server.js"])
        let instances = InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances
        #expect(instances.map(\.pid) == [400])
        #expect(instances.first?.profile == .default)
    }

    @Test(arguments: [
        ("cli", InstanceKind.cli), ("claude-desktop", .desktopCode), ("claude-vscode", .ide),
        ("sdk-ts", .sdk), ("mystery", .other),
    ])
    func mapsEntrypoints(entrypoint: String, kind: InstanceKind) {
        #expect(InstanceKind(entrypoint: entrypoint) == kind)
    }
}
