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

    /// A path compares the same before and after it exists. On macOS the temporary
    /// dir sits behind the `/var` symlink, so this also covers `/private`.
    @Test func aMissingPathIsCanonicalLikeItsExistingParent() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let missing = sandbox.root.appending(path: "not/yet", directoryHint: .isDirectory)

        #expect(missing.canonicalPath == sandbox.root.canonicalPath + "/not/yet")

        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        #expect(missing.canonicalPath == sandbox.root.canonicalPath + "/not/yet")
    }

    @Test func aMissingPathBelowASymlinkIsCanonicalLikeTheSamePathBelowItsTarget() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let real = try sandbox.makeDirectory("real")
        let alias = sandbox.root.appending(path: "alias", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)

        #expect(alias.appending(path: "missing").canonicalPath == real.appending(path: "missing").canonicalPath)
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

    @Test func aShortcutIsRefusedWhenAnotherClaimantIsUnreadable() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("acme"))
        try sandbox.store.create(ProfileName("work"))
        try setShortcut("w", of: "acme", in: sandbox)
        try setShortcut("w", of: "work", in: sandbox)
        try corrupt("acme", in: sandbox)

        #expect {
            try sandbox.store.profile(matching: "w")
        } throws: { error in
            (error as? HatsError)?.message.contains("cannot check whether 'w' is a shortcut") == true
        }
    }

    @Test func exactNamesKeepWorkingWithABrokenSibling() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let work = try ProfileName("work")
        try sandbox.store.create(work, shortcut: .set(try ProfileName("w")))
        try sandbox.store.create(ProfileName("zeta"))
        try corrupt("zeta", in: sandbox)

        #expect(try sandbox.store.profile(matching: "work").name == work)
        #expect(try sandbox.store.profile(fullName: "work").name == work)
        #expect(try sandbox.store.profile(matching: "default").isDefault)
    }

    @Test func fullNameLookupReportsAnAmbiguousShortcutAsAConflict() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("acme"))
        try sandbox.store.create(ProfileName("work"))
        try setShortcut("w", of: "acme", in: sandbox)
        try setShortcut("w", of: "work", in: sandbox)

        #expect {
            try sandbox.store.profile(fullName: "w")
        } throws: { error in
            let refusal = error as? HatsError
            return refusal?.kind == .conflict && refusal?.message == "the shortcut 'w' is claimed by 'acme', 'work'"
        }
    }

    @Test func fullNameLookupReportsAnUnreadableProfileRatherThanAMissingOne() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("work"), shortcut: .set(try ProfileName("w")))
        try corrupt("work", in: sandbox)

        #expect {
            try sandbox.store.profile(fullName: "w")
        } throws: { error in
            let refusal = error as? HatsError
            return refusal?.kind == .io && refusal?.message.contains("cannot check whether 'w' is a shortcut") == true
        }
    }

    @Test func fullNameLookupStillReportsAMissingProfile() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        #expect {
            try sandbox.store.profile(fullName: "ghost")
        } throws: { error in
            (error as? HatsError)?.kind == .notFound
        }
    }

    @Test func instanceFilterResolvesAShortcutToItsProfilesInstances() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (work, _) = try sandbox.store.create(ProfileName("work"), shortcut: .set(try ProfileName("w")))
        let table = FakeProcessTable()
        table.addDesktop(pid: 100, userDataDir: work.desktopDir.plainPath, configDir: work.codeDir.plainPath)

        let filter = try sandbox.store.instanceFilter(matching: "w")

        #expect(filter == work.name)
        let instances = InstanceScanner(profiles: try sandbox.store.list(), processes: table).scan().instances
        #expect(instances.filter { $0.profile == filter }.map(\.pid) == [100])
    }

    @Test func instanceFilterFallsBackToTheTypedNameOnlyWhenNoProfileHasIt() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        #expect(try sandbox.store.instanceFilter(matching: "ghost").rawValue == "ghost")
    }

    @Test func instanceFilterRefusesAnAmbiguousShortcut() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("acme"))
        try sandbox.store.create(ProfileName("work"))
        try setShortcut("w", of: "acme", in: sandbox)
        try setShortcut("w", of: "work", in: sandbox)

        #expect {
            try sandbox.store.instanceFilter(matching: "w")
        } throws: { error in
            (error as? HatsError)?.kind == .conflict
        }
    }

    @Test(arguments: ["zeta", "w", "ghost"])
    func instanceFilterRefusesWhatAnUnreadableProfileMayOwn(typed: String) throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("zeta"), shortcut: .set(try ProfileName("w")))
        try corrupt("zeta", in: sandbox)

        #expect {
            try sandbox.store.instanceFilter(matching: typed)
        } throws: { error in
            (error as? HatsError)?.kind == .io
        }
    }

    @Test func aRerunIsNotBlockedByAStoredShortcutOrName() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let w = try ProfileName("w")
        let work = try ProfileName("work")
        try sandbox.store.create(w)
        try sandbox.store.create(work)
        try setShortcut("w", of: "work", in: sandbox)
        let red = try ProfileColor(parsing: "red")

        #expect(try sandbox.store.create(work, color: red).profile.color == red)
        #expect(try sandbox.store.create(work).profile.shortcut == w)
        #expect(try sandbox.store.create(w, color: red).profile.color == red)
    }

    @Test func settingAConflictingShortcutIsStillRefusedOnARerun() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let w = try ProfileName("w")
        let work = try ProfileName("work")
        try sandbox.store.create(w)
        try sandbox.store.create(work)
        try setShortcut("w", of: "work", in: sandbox)

        #expect {
            try sandbox.store.create(work, shortcut: .set(w))
        } throws: { error in
            (error as? HatsError)?.message == "the shortcut 'w' is the name of profile 'w'"
        }
    }

    @Test func clearingAClaimedShortcutResolvesTheConflict() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let acme = try ProfileName("acme")
        try sandbox.store.create(acme)
        try sandbox.store.create(ProfileName("work"))
        try setShortcut("w", of: "acme", in: sandbox)
        try setShortcut("w", of: "work", in: sandbox)

        try sandbox.store.create(acme, shortcut: .clear)

        #expect(try sandbox.store.profile(matching: "w").name.rawValue == "work")
    }

    @Test func aShortcutCannotBeTheProfilesOwnName() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let work = try ProfileName("work")

        #expect {
            try sandbox.store.create(work, shortcut: .set(work))
        } throws: { error in
            let refusal = error as? HatsError
            return refusal?.kind == .usage && refusal?.message == "the shortcut 'work' is the profile's own name"
        }
        #expect(!sandbox.store.exists(work))
    }

    @Test func aNameThatIsAShortcutIsRefusedWithAHintThatKeepsTheShortcut() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("work"), shortcut: .set(try ProfileName("w")))

        #expect {
            try sandbox.store.create(ProfileName("w"))
        } throws: { error in
            let hint = (error as? HatsError)?.hint
            return hint?.hasPrefix("to change it, run: hats add work;") == true && hint?.contains("pick another name") == true
        }
    }

    @Test func aRefusalWhileASiblingIsUnreadableNamesTheShortcutThatWasAskedFor() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("zeta"))
        try corrupt("zeta", in: sandbox)

        #expect {
            try sandbox.store.create(ProfileName("work"), shortcut: .set(try ProfileName("w")))
        } throws: { error in
            (error as? HatsError)?.message.contains("cannot check that the shortcut 'w' is unused") == true
        }
        #expect(!sandbox.store.exists(try ProfileName("work")))
    }

    @Test func doctorReportsAShortcutTwoProfilesClaim() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("acme"))
        try sandbox.store.create(ProfileName("work"))
        try setShortcut("w", of: "acme", in: sandbox)
        try setShortcut("w", of: "work", in: sandbox)

        let findings = sandbox.doctor().run().filter { $0.check == "shortcuts" }

        #expect(findings.count == 1)
        #expect(findings.first?.level == .warn)
        #expect(findings.first?.message == "profiles acme, work claim the shortcut 'w', so commands refuse it")
        #expect(findings.first?.hint == "keep it on one of them, for example: hats add acme --no-shortcut")
    }

    @Test func doctorReportsAShortcutThatIsAnotherProfilesName() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("w"))
        try sandbox.store.create(ProfileName("work"))
        try setShortcut("w", of: "work", in: sandbox)

        let findings = sandbox.doctor().run().filter { $0.check == "shortcuts" }

        #expect(findings.count == 1)
        #expect(findings.first?.level == .warn)
        #expect(findings.first?.message == "the shortcut 'w' of profile 'work' is also a profile's name, which wins")
        #expect(findings.first?.hint == "remove it with: hats add work --no-shortcut")
    }

    @Test func doctorIsQuietAboutShortcutsThatAreFine() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("acme"), shortcut: .set(try ProfileName("a")))
        try sandbox.store.create(ProfileName("work"), shortcut: .set(try ProfileName("w")))

        #expect(!sandbox.doctor().run().contains { $0.check == "shortcuts" })
    }

    @Test func doctorDoesNotSuggestAdoptingUnderAShortcut() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.store.create(ProfileName("work"), shortcut: .set(try ProfileName("w")))
        let table = FakeProcessTable()
        table.addCLI(pid: 300, configDir: "/Users/alice/.claude-w")

        let findings = sandbox.doctor(processes: table).run()

        #expect(findings.contains { $0.hint == "adopt it with: hats add <name> --code-dir /Users/alice/.claude-w" })
    }

    @Test func aSuggestedNameIsDroppedWhenItIsAShortcut() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let w = try ProfileName("w")
        let (work, _) = try sandbox.store.create(ProfileName("work"), shortcut: .set(w))

        #expect(w.unlessShortcut(in: [work]) == nil)
        #expect(work.name.unlessShortcut(in: [work]) == work.name)
        #expect(w.unlessShortcut(in: []) == w)
    }

    private func corrupt(_ profile: String, in sandbox: Sandbox) throws {
        try Data("{ not json".utf8).write(to: sandbox.layout.metadataFile(try ProfileName(profile)))
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
