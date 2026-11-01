import Foundation
import Testing
@testable import HatsCore

@Suite struct PurgeTests {
    @Test func movesTheProfileToTheDiscarderInsteadOfDeletingIt() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        try Data("keep".utf8).write(to: work.desktopDir.appending(path: "config.json"))

        try sandbox.store.purge(work.name, processes: FakeProcessTable(), discarder: sandbox.discarder)
        #expect(!sandbox.store.exists(work.name))
        let trashed = try FileManager.default.contentsOfDirectory(atPath: sandbox.root.appending(path: "trash").plainPath)
        #expect(trashed.count == 1)
    }

    @Test func neverPurgesARunningProfile() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let table = FakeProcessTable()
        table.addDesktop(pid: 101, userDataDir: work.desktopDir.plainPath, configDir: work.codeDir.plainPath)

        let error = try #require(throws: HatsError.self) {
            try sandbox.store.purge(work.name, processes: table, discarder: sandbox.discarder)
        }
        #expect(error.kind == .conflict)
        #expect(sandbox.store.exists(work.name))
    }
}

@Suite struct DuplicateInstanceTests {
    @Test func keepsTheOldestInstancePerDataDir() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let table = FakeProcessTable()
        table.addDesktop(
            pid: 30, userDataDir: work.desktopDir.plainPath, configDir: work.codeDir.plainPath, start: Date(timeIntervalSince1970: 300))
        table.addDesktop(
            pid: 10, userDataDir: work.desktopDir.plainPath, configDir: work.codeDir.plainPath, start: Date(timeIntervalSince1970: 100))
        table.addDesktop(
            pid: 20, userDataDir: work.desktopDir.plainPath, configDir: work.codeDir.plainPath, start: Date(timeIntervalSince1970: 200))
        table.addDesktop(pid: 40, userDataDir: nil, configDir: nil)

        let scan = InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan()
        let groups = DuplicateInstances.groups(in: scan.instances)
        #expect(groups.count == 1)
        #expect(groups[0].keep.pid == 10)
        #expect(groups[0].extras.map(\.pid) == [20, 30])
    }

    @Test func aRelaunchedProfileWindowShowsUpAsADefaultDuplicate() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let table = FakeProcessTable()
        table.addDesktop(pid: 10, userDataDir: nil, configDir: nil, start: Date(timeIntervalSince1970: 100))
        table.addDesktop(pid: 11, userDataDir: nil, configDir: "/somewhere/code", start: Date(timeIntervalSince1970: 900))

        let findings = sandbox.doctor(processes: table).run()
        let duplicate = try #require(findings.first { $0.message.contains("2 Desktop instances share profile 'default'") })
        #expect(duplicate.hint?.contains("hats dedupe") == true)
        #expect(duplicate.hint?.contains("hats open --all") == true)
    }
}

@Suite struct ResetTests {
    @Test func movesDesktopDataAwayAndRecreatesTheDir() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        try Data("{}".utf8).write(to: work.desktopDir.appending(path: "config.json"))
        try Data("keep".utf8).write(to: work.codeDir.appending(path: "settings.json"))

        let discarded = try sandbox.store.reset(work.name, includingCode: false, discarder: sandbox.discarder)
        #expect(discarded == [work.desktopDir])
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.desktopDir.plainPath).isEmpty)
        #expect(FileManager.default.fileExists(atPath: work.codeDir.appending(path: "settings.json").plainPath))
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.root.appending(path: "trash").plainPath).count == 1)
    }

    @Test func includingCodeResetsAnOwnedCodeDir() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        try Data("x".utf8).write(to: work.codeDir.appending(path: "settings.json"))
        try sandbox.store.reset(work.name, includingCode: true, discarder: sandbox.discarder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.codeDir.plainPath).isEmpty)
    }

    @Test func neverDiscardsAnAdoptedCodeDirOrTheDefault() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let adopted = try sandbox.makeDirectory("home/.claude-work")
        let (work, _) = try sandbox.store.create(ProfileName("work"), adoptingCodeDir: adopted)
        #expect(throws: HatsError.self) { try sandbox.store.reset(work.name, includingCode: true, discarder: sandbox.discarder) }
        #expect(throws: HatsError.self) { try sandbox.store.reset(.default, includingCode: false, discarder: sandbox.discarder) }
        #expect(FileManager.default.fileExists(atPath: adopted.plainPath))
    }
}

@Suite struct DockEditorTests {
    let claude = URL(filePath: "/Applications/Claude.app", directoryHint: .isDirectory)
    let work = URL(filePath: "/Users/alice/Applications/Hats/Claude (Work).app", directoryHint: .isDirectory)
    let personal = URL(filePath: "/Users/alice/Applications/Hats/Claude (Personal).app", directoryHint: .isDirectory)
    let safari = URL(filePath: "/Applications/Safari.app", directoryHint: .isDirectory)

    @Test func pinsAfterClaudeAndKeepsLaunchersTogether() throws {
        let dock = FakeDockPreferences()
        dock.apps = [
            DockEditor.tile(for: safari, now: Date()), DockEditor.tile(for: claude, now: Date()), DockEditor.tile(for: safari, now: Date()),
        ]
        let editor = DockEditor(preferences: dock)

        #expect(try editor.pin([work], dedupeClaude: claude) == [.pinned(work)])
        #expect(try editor.pin([personal], dedupeClaude: claude) == [.pinned(personal)])
        #expect(
            editor.pinnedURLs().map(\.lastPathComponent) == [
                "Safari.app", "Claude.app", "Claude (Work).app", "Claude (Personal).app", "Safari.app",
            ])
        #expect(dock.restarts == 2)
    }

    @Test func isIdempotentAndDoesNotRestartTheDockForNothing() throws {
        let dock = FakeDockPreferences()
        let editor = DockEditor(preferences: dock)
        _ = try editor.pin([work])
        #expect(try editor.pin([work]) == [.alreadyPinned(work)])
        #expect(dock.writes == 1)
        #expect(dock.restarts == 1)
    }

    @Test func repairsTilesTheDockIgnores() throws {
        let dock = FakeDockPreferences()
        var broken = DockEditor.tile(for: work, now: Date())
        var data = broken["tile-data"] as! [String: Any]
        data["file-mod-date"] = 0
        broken["tile-data"] = data
        dock.apps = [broken]
        #expect(try DockEditor(preferences: dock).pin([work]) == [.repaired(work)])
        #expect(DockEditor.isValid(dock.apps[0]))
        #expect(dock.apps.count == 1)
    }

    @Test func dedupeKeepsOneClaudePinAndLeavesOthersAlone() throws {
        let dock = FakeDockPreferences()
        dock.apps = [claude, safari, claude, claude].map { DockEditor.tile(for: $0, now: Date()) }
        let changes = try DockEditor(preferences: dock).pin([work], dedupeClaude: claude)
        #expect(changes == [.removedDuplicateClaude(count: 2), .pinned(work)])
        #expect(dock.apps.compactMap(DockEditor.url(of:)).map(\.lastPathComponent) == ["Claude.app", "Claude (Work).app", "Safari.app"])
    }

    @Test func unpinRemovesOnlyTheGivenLaunchers() throws {
        let dock = FakeDockPreferences()
        dock.apps = [claude, work, personal].map { DockEditor.tile(for: $0, now: Date()) }
        #expect(try DockEditor(preferences: dock).unpin([work]) == [.unpinned(work)])
        #expect(dock.apps.compactMap(DockEditor.url(of:)).map(\.lastPathComponent) == ["Claude.app", "Claude (Personal).app"])
    }

    @Test func tileURLsArePercentEncodedFileURLs() {
        let tile = DockEditor.tile(for: work, now: Date(timeIntervalSince1970: 0))
        let file = (tile["tile-data"] as! [String: Any])["file-data"] as! [String: Any]
        #expect(file["_CFURLString"] as? String == "file:///Users/alice/Applications/Hats/Claude%20(Work).app/")
        #expect((tile["tile-data"] as! [String: Any])["file-mod-date"] as? Int64 == 2_082_844_800)
    }
}

@Suite struct DesktopCopyTests {
    @Test func copiesAreRefreshedOnRebuildAndRemovedWithTheLauncher() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let builder = sandbox.launchers
        let name = try ProfileName("work")
        try builder.build(for: try sandbox.store.create(name).profile, hatsPath: "/usr/bin/true")
        let copy = try builder.copy(for: name, to: sandbox.layout.desktopFolder)
        #expect(copy.lastPathComponent == "Claude (Work).app")

        try builder.build(for: try sandbox.store.create(name, label: "Acme").profile, hatsPath: "/usr/bin/true")
        #expect(builder.installed(in: sandbox.layout.desktopFolder).map(\.bundle.lastPathComponent) == ["Claude (Acme).app"])

        try builder.remove(for: name)
        #expect(builder.installed(in: sandbox.layout.desktopFolder).isEmpty)
        #expect(try builder.installed().isEmpty)
    }
}

extension DesktopCopyTests {
    /// Listing ~/Desktop can raise a privacy prompt, so only copies hats made
    /// itself (or the user asked for) are ever looked at.
    @Test func leavesUnrecordedDesktopBundlesAlone() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let builder = sandbox.launchers
        let name = try ProfileName("work")
        let launcher = try builder.build(for: try sandbox.store.create(name).profile, hatsPath: "/usr/bin/true")
        let desktop = try sandbox.makeDirectory("home/Desktop")
        let handMade = desktop.appending(path: launcher.lastPathComponent, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: launcher, to: handMade)

        try builder.build(for: try sandbox.store.create(name, label: "Acme").profile, hatsPath: "/usr/bin/true")
        try builder.remove(for: name)
        #expect(try FileManager.default.contentsOfDirectory(atPath: desktop.plainPath) == [handMade.lastPathComponent])
    }
}

@Suite struct DoctorAccountTests {
    @Test func flagsTwoProfilesOnOneAccount() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        let (personal, _) = try sandbox.store.create(ProfileName("personal"))
        for profile in [work, personal] {
            try writeJSON(
                ["oauth:tokenCache": "x", "lastKnownAccountUuid": "acct-1"], to: profile.desktopDir.appending(path: "config.json"))
        }
        let finding = try #require(sandbox.doctor().run().first { $0.check == "accounts" })
        #expect(finding.message == "profiles personal, work are signed in to the same Claude account")
        #expect(finding.hint == "if one of them should use another account, run: hats reset personal")
    }

    @Test func flagsASplitProfileAndANeverOpenedOne() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        try sandbox.store.create(ProfileName("acme"))
        try writeJSON(["oauth:tokenCache": "x", "lastKnownAccountUuid": "acct-1"], to: work.desktopDir.appending(path: "config.json"))
        try writeJSON(
            ["oauthAccount": ["accountUuid": "acct-2", "emailAddress": "me@home.example"]], to: work.codeDir.appending(path: ".claude.json")
        )

        let findings = sandbox.doctor().run()
        #expect(
            findings.contains { $0.check == "profile:work" && $0.message.contains("(me@home.example) are signed in to different accounts") }
        )
        #expect(findings.contains { $0.check == "profile:acme" && $0.message == "Claude Desktop was never opened" })
    }

    @Test func reportsTheClaudeURLHandler() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        #expect(sandbox.doctor().run().contains { $0.check == "sign-in" && $0.level == .warn })
        let foreign = try sandbox.makeDirectory("Other.app")
        #expect(
            sandbox.doctor(claudeURLHandler: foreign).run().contains { $0.check == "sign-in" && $0.message.contains("not Claude Desktop") })
    }
}

@Suite struct AdoptionCandidateTests {
    @Test func findsHandMadeConfigDirsThatNoProfileUses() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let work = try sandbox.makeDirectory("home/.claude-work")
        try Data("{}".utf8).write(to: work.appending(path: ".claude.json"))
        let client = try sandbox.makeDirectory("home/.claude.client/projects")
        _ = try sandbox.makeDirectory("home/.claude-empty")
        _ = try sandbox.makeDirectory("home/.claude/projects")
        let adopted = try sandbox.makeDirectory("home/.claude-old/projects").deletingLastPathComponent()
        try sandbox.store.create(ProfileName("old"), adoptingCodeDir: adopted)

        let table = FakeProcessTable()
        table.addCLI(pid: 50, configDir: "/elsewhere/.claude-live")
        let instances = InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances
        let found = AdoptionCandidates.find(layout: sandbox.layout, profiles: try sandbox.store.list(), instances: instances)
        #expect(found.map(\.lastPathComponent) == [".claude-live", ".claude-work", ".claude.client"])
        #expect(client.deletingLastPathComponent().lastPathComponent == ".claude.client")
    }

    @Test func suggestsNamesFromDirNames() {
        #expect(ProfileName.suggested(forConfigDir: URL(filePath: "/u/.claude-Work"))?.rawValue == "work")
        #expect(ProfileName.suggested(forConfigDir: URL(filePath: "/u/.claude.client"))?.rawValue == "client")
        #expect(ProfileName.suggested(forConfigDir: URL(filePath: "/u/.claude-default")) == nil)
        #expect(ProfileName.suggested(forConfigDir: URL(filePath: "/u/.claude")) == nil)
    }
}
