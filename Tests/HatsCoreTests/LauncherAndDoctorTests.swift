import Foundation
import Testing
@testable import HatsCore

/// Activation fails because the instance exits while it is being focused.
private final class ExitingAppControl: AppControl, @unchecked Sendable {
    let table: FakeProcessTable
    let inner = FakeAppControl()

    init(table: FakeProcessTable) {
        self.table = table
    }

    func launch(appURL: URL, newInstance: Bool, arguments: [String], environment: [String: String]) async throws -> Int32 {
        try await inner.launch(appURL: appURL, newInstance: newInstance, arguments: arguments, environment: environment)
    }

    @MainActor func activate(pid: Int32) -> Bool {
        table.processes.removeAll { $0.summary.pid == pid }
        return false
    }

    @MainActor func isRegularApp(pid: Int32) -> Bool { inner.isRegularApp(pid: pid) }

    @MainActor func terminate(pid: Int32) -> Bool { inner.terminate(pid: pid) }
}

@Suite struct DesktopLauncherTests {
    func makeClaudeApp(in sandbox: Sandbox) throws -> String {
        try sandbox.makeDirectory("Claude.app/Contents").deletingLastPathComponent().plainPath
    }

    @Test @MainActor func focusesARunningInstanceInsteadOfLaunching() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let table = FakeProcessTable()
        table.addDesktop(pid: 101, userDataDir: work.desktopDir.plainPath, configDir: work.codeDir.plainPath)
        let control = FakeAppControl()
        control.regularApps = [101]
        var environment = sandbox.environment
        environment["HATS_CLAUDE_APP"] = try makeClaudeApp(in: sandbox)

        let launcher = DesktopLauncher(
            layout: sandbox.layout, processes: table, control: control, environment: environment, appSearch: .nowhere)
        let outcome = try await launcher.open(work, among: try sandbox.store.list())
        #expect(outcome == .focused(pid: 101))
        #expect(control.launches.isEmpty)
    }

    @Test @MainActor func launchesAnIsolatedNewInstance() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let control = FakeAppControl()
        var environment = sandbox.environment
        let app = try makeClaudeApp(in: sandbox)
        environment["HATS_CLAUDE_APP"] = app

        let launcher = DesktopLauncher(
            layout: sandbox.layout, processes: FakeProcessTable(), control: control, environment: environment,
            appSearch: .nowhere)
        #expect(try await launcher.open(work, among: try sandbox.store.list()) == .launched(pid: 9_999))
        let launch = try #require(control.launches.first)
        #expect(launch.newInstance)
        #expect(launch.appURL.plainPath == app)
        #expect(launch.arguments == ["--user-data-dir=\(work.desktopDir.plainPath)"])
        #expect(launch.environment == ["CLAUDE_CONFIG_DIR": work.codeDir.plainPath])
    }

    @Test @MainActor func neverLaunchesASecondInstanceWhenTheRunningOneCannotBeFocused() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let table = FakeProcessTable()
        table.addDesktop(pid: 101, userDataDir: work.desktopDir.plainPath, configDir: work.codeDir.plainPath)
        let control = FakeAppControl()
        var environment = sandbox.environment
        environment["HATS_CLAUDE_APP"] = try makeClaudeApp(in: sandbox)

        let launcher = DesktopLauncher(
            layout: sandbox.layout, processes: table, control: control, environment: environment, appSearch: .nowhere)
        do {
            let outcome = try await launcher.open(work, among: try sandbox.store.list())
            Issue.record("expected a conflict error, got \(outcome)")
        } catch let error as HatsError {
            #expect(error.kind == .conflict)
        }
        #expect(control.launches.isEmpty)
    }

    @Test @MainActor func launchesWhenTheRunningInstanceExitsBeforeTheRescan() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let table = FakeProcessTable()
        table.addDesktop(pid: 101, userDataDir: work.desktopDir.plainPath, configDir: work.codeDir.plainPath)
        let control = ExitingAppControl(table: table)
        var environment = sandbox.environment
        environment["HATS_CLAUDE_APP"] = try makeClaudeApp(in: sandbox)

        let launcher = DesktopLauncher(
            layout: sandbox.layout, processes: table, control: control, environment: environment, appSearch: .nowhere)
        #expect(try await launcher.open(work, among: try sandbox.store.list()) == .launched(pid: 9_999))
        #expect(control.inner.launches.count == 1)
        #expect(control.inner.launches.first?.newInstance == true)
    }

    @Test @MainActor func defaultProfileOpensStockAppNormally() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let control = FakeAppControl()
        var environment = sandbox.environment
        environment["HATS_CLAUDE_APP"] = try makeClaudeApp(in: sandbox)
        let launcher = DesktopLauncher(
            layout: sandbox.layout, processes: FakeProcessTable(), control: control, environment: environment,
            appSearch: .nowhere)
        _ = try await launcher.open(sandbox.store.defaultProfile, among: try sandbox.store.list())
        #expect(control.launches.first?.newInstance == false)
        #expect(control.launches.first?.arguments == [])
    }

    @Test @MainActor func stockAppThatCannotBeFocusedIsStillOpenedNormally() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let table = FakeProcessTable()
        table.addDesktop(pid: 101, userDataDir: nil, configDir: nil)
        let control = FakeAppControl()
        var environment = sandbox.environment
        environment["HATS_CLAUDE_APP"] = try makeClaudeApp(in: sandbox)

        let launcher = DesktopLauncher(
            layout: sandbox.layout, processes: table, control: control, environment: environment, appSearch: .nowhere)
        #expect(try await launcher.open(sandbox.store.defaultProfile, among: try sandbox.store.list()) == .launched(pid: 9_999))
        #expect(control.launches.first?.newInstance == false)
    }

    @Test @MainActor func resolvesHostAppThroughParentChain() {
        let table = FakeProcessTable()
        table.addApp(pid: 50, command: "iTerm2")
        table.addApp(pid: 60, parent: 50, command: "zsh")
        table.addCLI(pid: 70, parent: 60, configDir: nil)
        let control = FakeAppControl()
        control.regularApps = [50]
        #expect(HostAppResolver(processes: table, control: control).hostApp(of: 70) == 50)
        #expect(HostAppResolver(processes: table, control: FakeAppControl()).hostApp(of: 70) == nil)
    }
}

@Suite struct DoctorTests {
    @Test func flagsDesktopStartedWithoutConfigDirAndDuplicates() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        try sandbox.launchers.build(for: work, hatsPath: "/usr/bin/true")
        let table = FakeProcessTable()
        table.addDesktop(pid: 101, userDataDir: work.desktopDir.plainPath, configDir: nil)
        table.addDesktop(pid: 102, userDataDir: work.desktopDir.plainPath, configDir: work.codeDir.plainPath)

        let findings = sandbox.doctor(processes: table).run()
        #expect(findings.contains { $0.level == .fail && $0.message.contains("pid 101") && $0.message.contains("CLAUDE_CONFIG_DIR") })
        #expect(findings.contains { $0.level == .warn && $0.message.contains("2 Desktop instances") })
        #expect(!findings.contains { $0.level == .fail && $0.message.contains("pid 102") })
    }

    @Test func suggestsAdoptingUnmanagedConfigDirs() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let table = FakeProcessTable()
        table.addCLI(pid: 300, configDir: "/Users/alice/.claude-work")
        let findings = sandbox.doctor(processes: table).run()
        #expect(findings.contains { $0.hint == "adopt it with: hats add work --code-dir /Users/alice/.claude-work" })
    }

    @Test func reportsLoginAndLauncherState() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let probe = FakeCredentialProbe(present: [work.codeDir.plainPath])
        let findings = sandbox.doctor(credentials: probe).run()
        #expect(findings.contains { $0.check == "profile:work" && $0.message == "Claude Code login present" })
        #expect(findings.contains { $0.check == "profile:work" && $0.message == "no launcher" })
        #expect(findings.contains { $0.check == "profile:default" && $0.level == .warn })
    }
}

@Suite struct ClaudeAppTests {
    @Test func overrideWinsAndMustExist() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let app = try sandbox.makeDirectory("Custom/Claude.app/Contents")
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "9.9.9"], format: .xml, options: 0)
            .write(to: app.appending(path: "Info.plist"))
        var environment = sandbox.environment
        environment["HATS_CLAUDE_APP"] = app.deletingLastPathComponent().plainPath
        let located = try ClaudeApp.locate(layout: sandbox.layout, environment: environment, search: .nowhere)
        #expect(located.version == "9.9.9")

        environment["HATS_CLAUDE_APP"] = sandbox.root.appending(path: "Missing.app").plainPath
        #expect(throws: HatsError.self) {
            try ClaudeApp.locate(layout: sandbox.layout, environment: environment, search: .nowhere)
        }
    }

    @Test func looksUpTheBundleIDBeforeTheInstallLocations() {
        let layout = Layout(environment: ["HOME": "/home/me"])
        let found = URL(filePath: "/found/Claude.app", directoryHint: .isDirectory)
        let search = ClaudeAppSearch.installed { $0 == ClaudeApp.bundleIdentifier ? found : nil }
        #expect(
            search.candidates(layout).map(\.plainPath) == [
                "/found/Claude.app", "/Applications/Claude.app", "/home/me/Applications/Claude.app",
            ])
    }

    @Test func takesTheFirstCandidateThatExists() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let app = try sandbox.makeDirectory("Elsewhere/Claude.app")
        let missing = sandbox.root.appending(path: "Missing.app")
        let located = try ClaudeApp.locate(
            layout: sandbox.layout, environment: sandbox.environment, search: ClaudeAppSearch { _ in [missing, app] })
        #expect(located.url.plainPath == app.plainPath)
    }
}

#if canImport(Security)
@Suite struct CredentialProbeTests {
    @Test func namesKeychainItemsLikeClaudeCode() {
        #expect(
            KeychainCredentialProbe.serviceName(forConfigDir: URL(filePath: "/Users/a/.claude"), isDefault: true)
                == "Claude Code-credentials")
        let named = KeychainCredentialProbe.serviceName(
            forConfigDir: URL(filePath: "/x/code/", directoryHint: .isDirectory), isDefault: false)
        #expect(named == KeychainCredentialProbe.serviceName(forConfigDir: URL(filePath: "/x/code"), isDefault: false))
        #expect(named.wholeMatch(of: /Claude Code-credentials-[0-9a-f]{8}/) != nil)
    }

    @Test(.tags(.integration)) func realProbeReportsAbsentForUnknownDir() {
        let dir = URL(filePath: "/nonexistent/hats-\(UUID().uuidString)")
        #expect(KeychainCredentialProbe().state(forConfigDir: dir, isDefault: false) == .absent)
    }
}
#endif

@Suite struct AbbreviatingHomeTests {
    private let layout = Layout(environment: ["HOME": "/home/me"])

    @Test func anEmptyHomeCountsAsUnset() {
        #expect(Layout(environment: ["HOME": ""]).home.plainPath == URL(filePath: NSHomeDirectory()).plainPath)
    }

    @Test(arguments: [
        ("/home/me", "~"), ("/home/me/a/b", "~/a/b"), ("/home/me2/a", "/home/me2/a"), ("/other", "/other"),
    ])
    func shortensOnlyPathsInsideHome(path: String, expected: String) {
        #expect(layout.abbreviatingHome(path) == expected)
    }
}
