import Foundation
import Testing
@testable import HatsCore

@Suite struct ProfileNameTests {
    @Test(arguments: ["work", "a", "client-acme", "x1", String(repeating: "a", count: 32)])
    func acceptsValidNames(_ raw: String) throws {
        #expect(try ProfileName(raw).rawValue == raw)
    }

    @Test(arguments: ["", "Work", "-work", "work_2", "a/b", "..", "work ", "wörk", String(repeating: "a", count: 33)])
    func rejectsInvalidNames(_ raw: String) {
        #expect(throws: HatsError.self) { try ProfileName(raw) }
    }

    @Test func derivesLabel() throws {
        #expect(try ProfileName("client-acme").defaultLabel == "Client Acme")
    }
}

@Suite struct ProfileColorTests {
    @Test func parsesHex() throws {
        let color = try ProfileColor(hex: "#2E7D32")
        #expect(color == ProfileColor(red: 0x2E, green: 0x7D, blue: 0x32))
        #expect(color.description == "#2E7D32")
    }

    @Test(arguments: [
        ("blue", "#1565C0"), ("green", "#2E7D32"), ("red", "#C62828"), ("purple", "#6A1B9A"),
        ("orange", "#BF360C"), ("teal", "#00695C"), ("pink", "#AD1457"), ("brown", "#4E342E"),
    ])
    func parsesNames(_ name: String, _ hex: String) throws {
        #expect(try ProfileColor(parsing: name) == ProfileColor(hex: hex))
    }

    @Test(arguments: ["Green", "GREEN", " green "])
    func namesIgnoreCaseAndSpaces(_ raw: String) throws {
        #expect(try ProfileColor(parsing: raw) == ProfileColor(hex: "#2E7D32"))
    }

    @Test(arguments: ["#2E7D32", "2e7d32"])
    func acceptsHexWhereNamesAreAccepted(_ raw: String) throws {
        #expect(try ProfileColor(parsing: raw) == ProfileColor(hex: "#2E7D32"))
    }

    @Test(arguments: ["yellow", "", "#12345", "#GGGGGG"])
    func rejectsUnknownColors(_ raw: String) {
        #expect {
            try ProfileColor(parsing: raw)
        } throws: { error in
            (error as? HatsError)?.hint?.contains("blue, green, red, purple, orange, teal, pink, brown or #RRGGBB") == true
        }
    }

    @Test func namedColorsAreThePaletteInOrder() {
        #expect(ProfileColor.named.map(\.color) == ProfileColor.palette)
    }

    @Test func storesNamedColorsAsHex() throws {
        let data = try JSONEncoder().encode(try ProfileColor(parsing: "teal"))
        #expect(String(decoding: data, as: UTF8.self) == "\"#00695C\"")
    }

    @Test func automaticColorIsStable() throws {
        let name = try ProfileName("work")
        #expect(ProfileColor.automatic(for: name) == ProfileColor.automatic(for: name))
        #expect(ProfileColor.palette.contains(ProfileColor.automatic(for: name)))
    }

    @Test func paletteUsesWhiteGlyphs() {
        #expect(ProfileColor.palette.allSatisfy { !$0.prefersDarkGlyph })
        #expect(ProfileColor(red: 255, green: 235, blue: 59).prefersDarkGlyph)
    }
}

@Suite struct LayoutTests {
    @Test func honoursOverridesAndIgnoresInheritedConfigDir() {
        let layout = Layout(environment: [
            "HOME": "/Users/alice", "HATS_HOME": "/tmp/hh", "HATS_LAUNCHER_DIR": "/tmp/apps",
            "CLAUDE_CONFIG_DIR": "/tmp/somewhere-else",
        ])
        #expect(layout.hatsHome.plainPath == "/tmp/hh")
        #expect(layout.launcherDir.plainPath == "/tmp/apps")
        #expect(layout.defaultCodeDir.plainPath == "/Users/alice/.claude")
        #expect(layout.defaultDesktopDir.plainPath == "/Users/alice/Library/Application Support/Claude")
    }

    @Test func strictInsideCheck() {
        let root = URL(filePath: "/a/b")
        #expect(Layout.isStrictlyInside(URL(filePath: "/a/b/c"), root: root))
        #expect(!Layout.isStrictlyInside(URL(filePath: "/a/b"), root: root))
        #expect(!Layout.isStrictlyInside(URL(filePath: "/a/bc"), root: root))
        #expect(!Layout.isStrictlyInside(URL(filePath: "/a/b/../c"), root: root))
    }
}

@Suite struct ProfileStoreTests {
    @Test func listsDefaultFirst() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("zeta"))
        try sandbox.store.create(ProfileName("alpha"))
        #expect(try sandbox.store.list().map(\.name.rawValue) == ["default", "alpha", "zeta"])
    }

    @Test func oneUnreadableProfileDoesNotHideTheOthers() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("alpha"))
        try sandbox.store.create(ProfileName("zeta"))
        let broken = try ProfileName("zeta")
        try Data("{ not json".utf8).write(to: sandbox.layout.metadataFile(broken))
        #expect(try sandbox.store.list().map(\.name.rawValue) == ["default", "alpha"])
    }

    @Test func removingAHealthyProfileWorksWhileASiblingIsUnreadable() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("alpha"))
        try sandbox.store.create(ProfileName("zeta"))
        let broken = try ProfileName("zeta")
        try Data("{ not json".utf8).write(to: sandbox.layout.metadataFile(broken))
        let alpha = try ProfileName("alpha")
        try sandbox.store.purge(alpha, processes: FakeProcessTable(), discarder: sandbox.discarder)
        #expect(!sandbox.store.exists(alpha))
    }

    @Test func inventoryReportsEachUnreadableProfileWithItsError() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("alpha"))
        try sandbox.store.create(ProfileName("beta"))
        try sandbox.store.create(ProfileName("zeta"))
        try Data("{ not json".utf8).write(to: sandbox.layout.metadataFile(try ProfileName("beta")))
        let zeta = try ProfileName("zeta")
        let newer = try String(contentsOf: sandbox.layout.metadataFile(zeta), encoding: .utf8).replacingOccurrences(
            of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
        try newer.write(to: sandbox.layout.metadataFile(zeta), atomically: true, encoding: .utf8)

        let inventory = try sandbox.store.inventory()
        #expect(inventory.profiles.map(\.name.rawValue) == ["default", "alpha"])
        #expect(inventory.unreadableProfiles.map(\.name.rawValue) == ["beta", "zeta"])
        #expect(inventory.unreadableProfiles.map(\.error.kind) == [.io, .environment])
    }

    @Test func profileNamedReportsTheSpecificErrorForAnUnreadableProfile() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("zeta"))
        let zeta = try ProfileName("zeta")
        try Data("{ not json".utf8).write(to: sandbox.layout.metadataFile(zeta))
        #expect {
            try sandbox.store.profile(named: zeta)
        } throws: { error in
            (error as? HatsError)?.kind == .io
        }
    }

    @Test func purgeRefusesAnUnreadableProfile() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("zeta"))
        let zeta = try ProfileName("zeta")
        try Data("{ not json".utf8).write(to: sandbox.layout.metadataFile(zeta))
        #expect(throws: HatsError.self) {
            try sandbox.store.purge(zeta, processes: FakeProcessTable(), discarder: sandbox.discarder)
        }
        #expect(FileManager.default.fileExists(atPath: sandbox.layout.profileDir(zeta).plainPath))
    }

    @Test func addAndAdoptionRefuseWithAClearErrorWhileASiblingIsUnreadable() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("zeta"))
        try Data("{ not json".utf8).write(to: sandbox.layout.metadataFile(try ProfileName("zeta")))
        let external = try sandbox.makeDirectory("home/.claude-work")
        do {
            try sandbox.store.create(ProfileName("work"), adoptingCodeDir: external)
            Issue.record("adoption should refuse while profile 'zeta' is unreadable")
        } catch {
            #expect(error.message.contains("'zeta'"))
            #expect(error.message.contains("cannot check whether"))
            #expect(error.message.contains("cannot be read"))
            #expect(error.hint != nil)
            #expect(error.hint?.contains("profile.json") == true)
        }
        do {
            try sandbox.store.create(ProfileName("acme"))
            Issue.record("add should refuse while profile 'zeta' is unreadable")
        } catch {
            #expect(error.message.contains("'zeta'"))
            #expect(error.message.contains("cannot check that the label"))
            #expect(error.message.contains("cannot be read"))
            #expect(error.hint != nil)
            #expect(error.hint?.contains("profile.json") == true)
        }
    }

    @Test func doctorReportsEachUnreadableProfileByName() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("alpha"))
        try sandbox.store.create(ProfileName("zeta"))
        try Data("{ not json".utf8).write(to: sandbox.layout.metadataFile(try ProfileName("zeta")))
        let findings = sandbox.doctor().run()
        #expect(findings.contains { $0.level == .fail && $0.check == "profile:zeta" })
        #expect(!findings.contains { $0.check == "profiles" })
        #expect(findings.contains { $0.check == "profile:alpha" })
    }

    @Test func createIsIdempotentAndKeepsData() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let name = try ProfileName("work")
        let (first, created) = try sandbox.store.create(name)
        #expect(created)
        let marker = first.codeDir.appending(path: "settings.json")
        try Data("{}".utf8).write(to: marker)

        let (second, createdAgain) = try sandbox.store.create(name, label: "Day Job")
        #expect(!createdAgain)
        #expect(second.label == "Day Job")
        #expect(second.createdAt == first.createdAt)
        #expect(FileManager.default.fileExists(atPath: marker.plainPath))
    }

    @Test func refusesDefault() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        #expect(throws: HatsError.self) { try sandbox.store.create(.default) }
        #expect(throws: HatsError.self) { try sandbox.store.purge(.default, processes: FakeProcessTable(), discarder: sandbox.discarder) }
    }

    @Test func adoptsExistingCodeDirAndNeverPurgesIt() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let external = try sandbox.makeDirectory("home/.claude-work")
        try Data("{}".utf8).write(to: external.appending(path: "settings.json"))

        let (profile, _) = try sandbox.store.create(ProfileName("work"), adoptingCodeDir: external)
        #expect(profile.codeDirIsExternal)
        #expect(profile.codeDir.plainPath == external.plainPath)
        #expect(!FileManager.default.fileExists(atPath: sandbox.layout.codeDir(profile.name).plainPath))

        try sandbox.store.purge(profile.name, processes: FakeProcessTable(), discarder: sandbox.discarder)
        #expect(FileManager.default.fileExists(atPath: external.appending(path: "settings.json").plainPath))
        #expect(!sandbox.store.exists(profile.name))
    }

    @Test func refusesToAdoptDefaultOrSharedDirs() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let defaultDir = try sandbox.makeDirectory("home/.claude")
        #expect(throws: HatsError.self) { try sandbox.store.create(ProfileName("a"), adoptingCodeDir: defaultDir) }

        let shared = try sandbox.makeDirectory("home/.claude-x")
        try sandbox.store.create(ProfileName("x"), adoptingCodeDir: shared)
        #expect(throws: HatsError.self) { try sandbox.store.create(ProfileName("y"), adoptingCodeDir: shared) }
        #expect(throws: HatsError.self) {
            try sandbox.store.create(ProfileName("z"), adoptingCodeDir: sandbox.root.appending(path: "missing"))
        }
    }

    @Test(arguments: ["Work", "work", "WORK"])
    func refusesALabelAnotherProfileUses(label: String) throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("work"))
        #expect(throws: HatsError.self) { try sandbox.store.create(ProfileName("acme"), label: label) }
        #expect(!sandbox.store.exists(try ProfileName("acme")))
    }

    @Test func refusesADerivedLabelAnotherProfileUses() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("work"), label: "Acme")
        #expect(throws: HatsError.self) { try sandbox.store.create(ProfileName("acme")) }
    }

    @Test func labelCollisionWithAReadableProfileNamesItsOwner() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("work"), label: "Acme")
        #expect {
            try sandbox.store.create(ProfileName("acme"), label: "acme")
        } throws: { error in
            (error as? HatsError)?.message == "the label 'acme' is already used by profile 'work'"
        }
    }

    @Test func keepingItsOwnLabelIsNotACollision() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let name = try ProfileName("work")
        try sandbox.store.create(name)
        #expect(try sandbox.store.create(name, label: "WORK").profile.label == "WORK")
    }

    @Test func shortcutResolvesToItsProfileAndSurvivesARewrite() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let work = try ProfileName("work")
        try sandbox.store.create(work, shortcut: .set(try ProfileName("w")))
        #expect(try sandbox.store.profile(matching: "w").name == work)

        try sandbox.store.create(work, label: "Day Job")
        #expect(try sandbox.store.profile(matching: "w").label == "Day Job")
    }

    @Test func clearingAShortcutFreesIt() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let work = try ProfileName("work")
        let w = try ProfileName("w")
        try sandbox.store.create(work, shortcut: .set(w))

        let (cleared, _) = try sandbox.store.create(work, shortcut: .clear)
        #expect(cleared.shortcut == nil)
        #expect(throws: HatsError.self) { try sandbox.store.profile(matching: "w") }
        #expect(try sandbox.store.create(w).created)
    }

    @Test func aProfileMayReplaceItsOwnShortcut() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let work = try ProfileName("work")
        try sandbox.store.create(work, shortcut: .set(try ProfileName("w")))
        #expect(try sandbox.store.create(work, shortcut: .set(try ProfileName("job"))).profile.shortcut?.rawValue == "job")
        #expect(try sandbox.store.create(work, shortcut: .set(try ProfileName("job"))).profile.shortcut?.rawValue == "job")
    }

    @Test func refusesAmbiguousShortcutsAndNames() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let w = try ProfileName("w")
        try sandbox.store.create(ProfileName("work"), shortcut: .set(w))
        try sandbox.store.create(ProfileName("acme"))

        #expect(throws: HatsError.self) { try sandbox.store.create(ProfileName("acme"), shortcut: .set(w)) }
        #expect(throws: HatsError.self) { try sandbox.store.create(ProfileName("acme"), shortcut: .set(try ProfileName("work"))) }
        #expect(throws: HatsError.self) { try sandbox.store.create(ProfileName("acme"), shortcut: .set(.default)) }
        #expect(throws: HatsError.self) { try sandbox.store.create(w) }
        #expect(!sandbox.store.exists(w))
    }

    @Test func aFullNameWinsOverAHandEditedShortcut() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("w"))
        try sandbox.store.create(ProfileName("work"))
        try setShortcut("w", of: "work", in: sandbox)

        #expect(try sandbox.store.profile(matching: "w").name.rawValue == "w")
    }

    @Test func aShortcutTwoProfilesClaimIsRefusedRatherThanGuessed() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("acme"))
        try sandbox.store.create(ProfileName("work"))
        try setShortcut("w", of: "acme", in: sandbox)
        try setShortcut("w", of: "work", in: sandbox)

        #expect {
            try sandbox.store.profile(matching: "w")
        } throws: { error in
            (error as? HatsError)?.kind == .conflict
        }
    }

    @Test func anUnknownNameIsNotReportedAsMissingWhileAProfileIsUnreadable() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("zeta"))
        try Data("{ not json".utf8).write(to: sandbox.layout.metadataFile(try ProfileName("zeta")))

        #expect {
            try sandbox.store.profile(matching: "w")
        } throws: { error in
            (error as? HatsError)?.message.contains("cannot check whether 'w' is a shortcut") == true
        }
    }

    @Test func fullNameLookupRefusesAShortcutAndAcceptsTheName() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let work = try ProfileName("work")
        try sandbox.store.create(work, shortcut: .set(try ProfileName("w")))

        #expect(try sandbox.store.profile(fullName: "work").name == work)
        #expect {
            try sandbox.store.profile(fullName: "w")
        } throws: { error in
            (error as? HatsError)?.hint == "this command takes the full name: work"
        }
    }

    private func setShortcut(_ shortcut: String, of profile: String, in sandbox: Sandbox) throws {
        let file = sandbox.layout.metadataFile(try ProfileName(profile))
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["shortcut"] = shortcut
        try JSONSerialization.data(withJSONObject: json).write(to: file)
    }

    @Test func refusesNewerSchema() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let name = try ProfileName("work")
        try sandbox.store.create(name)
        let file = sandbox.layout.metadataFile(name)
        let json = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(
            of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
        try json.write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: HatsError.self) { try sandbox.store.profile(named: name) }
    }

    @Test func addAndPurgeTouchNothingOutsideHatsRoots() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let home = sandbox.layout.home
        func snapshot() -> [String] {
            (FileManager.default.subpaths(atPath: home.plainPath) ?? []).sorted()
        }
        let before = snapshot()
        let name = try ProfileName("work")
        let (profile, _) = try sandbox.store.create(name)
        try sandbox.launchers.build(for: profile, hatsPath: "/usr/bin/true")
        try sandbox.launchers.remove(for: name)
        try sandbox.store.purge(name, processes: FakeProcessTable(), discarder: sandbox.discarder)
        #expect(snapshot() == before)
    }
}
