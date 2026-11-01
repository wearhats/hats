import Foundation
import Testing
@testable import HatsCore

@Suite struct IconTests {
    #if canImport(CoreGraphics)
    @Test(arguments: [IconRenderer.Glyph.letter("W"), .briefcase, .person])
    func rendersPNG(glyph: IconRenderer.Glyph) throws {
        let png = try IconRenderer.png(glyph: glyph, color: "#1565C0", size: 64)
        #expect(Array(png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
    #endif

    @Test func picksPictogramsForCommonNames() throws {
        #expect(LauncherIcon.automatic(for: try ProfileName("work")) == .briefcase)
        #expect(LauncherIcon.automatic(for: try ProfileName("personal")) == .person)
        #expect(LauncherIcon.automatic(for: try ProfileName("acme")) == .letter)
    }

    @Test func encodesICNSContainer() {
        let icns = ICNSEncoder.encode([(.icp4, Data([1, 2, 3])), (.ic10, Data([4]))])
        #expect(String(decoding: icns.prefix(4), as: UTF8.self) == "icns")
        #expect(icns.count == 8 + (8 + 3) + (8 + 1))
        #expect(Array(icns[4..<8]) == [0, 0, 0, UInt8(icns.count)])
        #expect(String(decoding: icns[8..<12], as: UTF8.self) == "icp4")
        #expect(Array(icns[12..<16]) == [0, 0, 0, 11])
    }
}

@Suite struct LauncherBuilderTests {
    @Test func buildsAValidBundle() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (profile, _) = try sandbox.store.create(ProfileName("work"))
        let bundle = try sandbox.launchers.build(for: profile, hatsPath: "/opt/homebrew/bin/hats")

        #expect(bundle.lastPathComponent == "Claude (Work).app")
        let contents = bundle.appending(path: "Contents")
        let info = try #require(NSDictionary(contentsOf: contents.appending(path: "Info.plist")) as? [String: Any])
        #expect(info["CFBundleIdentifier"] as? String == "dev.wearhats.launcher.work")
        #expect(info["CFBundleExecutable"] as? String == "launch")
        #expect(info["LSUIElement"] as? Bool == true)

        let script = contents.appending(path: "MacOS/launch")
        #expect(FileManager.default.isExecutableFile(atPath: script.plainPath))
        let source = try String(contentsOf: script, encoding: .utf8)
        #expect(source.contains("exec \"$HATS\" open 'work'"))
        #expect(source.contains("export HATS_HOME='\(sandbox.layout.hatsHome.plainPath)'"))
        #if canImport(CoreGraphics)
        let icns = try Data(contentsOf: contents.appending(path: "Resources/AppIcon.icns"))
        #expect(String(decoding: icns.prefix(4), as: UTF8.self) == "icns")
        #endif
        #expect(sandbox.launchers.status(for: profile.name)?.isCurrent == true)
    }

    @Test func relabelReplacesTheOldBundle() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let builder = sandbox.launchers
        let name = try ProfileName("work")
        try builder.build(for: try sandbox.store.create(name).profile, hatsPath: "/usr/bin/true")
        try builder.build(for: try sandbox.store.create(name, label: "Acme").profile, hatsPath: "/usr/bin/true")
        #expect(try builder.installed().map(\.bundle.lastPathComponent) == ["Claude (Acme).app"])
    }

    @Test func neverTouchesForeignBundles() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (profile, _) = try sandbox.store.create(ProfileName("work"))
        let foreign = try sandbox.makeDirectory("launchers/Claude (Work).app/Contents")
        #expect(throws: HatsError.self) {
            try sandbox.launchers.build(for: profile, hatsPath: "/usr/bin/true")
        }
        try sandbox.launchers.remove(for: profile.name)
        #expect(FileManager.default.fileExists(atPath: foreign.plainPath))
    }

    @Test func refusesToReplaceAnotherProfilesLauncher() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let builder = sandbox.launchers
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        try builder.build(for: work, hatsPath: "/usr/bin/true")
        let acme = try ProfileName("acme")
        let impostor = Profile(
            name: acme, label: "Work", color: .automatic(for: acme), desktopDir: sandbox.layout.desktopDir(acme),
            codeDir: sandbox.layout.codeDir(acme), createdAt: nil, codeDirIsExternal: false)

        #expect(throws: HatsError.self) { try builder.build(for: impostor, hatsPath: "/usr/bin/true") }
        #expect(try builder.installed().map(\.marker.name) == [work.name])
    }

    @Test func copyRefusesADestinationOwnedByAnotherProfile() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let builder = sandbox.launchers
        let work = try builder.build(for: try sandbox.store.create(ProfileName("work")).profile, hatsPath: "/usr/bin/true")
        let acme = try sandbox.store.create(ProfileName("acme")).profile
        try builder.build(for: acme, hatsPath: "/usr/bin/true")
        let elsewhere = try sandbox.makeDirectory("elsewhere")
        let taken = elsewhere.appending(path: "Claude (Acme).app", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: work, to: taken)

        let error = try #require(throws: HatsError.self) { try builder.copy(for: acme.name, to: elsewhere) }
        #expect(error.message.contains("'work'"))
        #expect(LauncherBuilder.marker(in: taken)?.name.rawValue == "work")
    }

    @Test func registersTheBundleThroughTheInjectedRegistrar() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let registrar = FakeRegistrar()
        let builder = LauncherBuilder(layout: sandbox.layout, registrar: registrar.registrar)
        let bundle = try builder.build(for: try sandbox.store.create(ProfileName("work")).profile, hatsPath: "/usr/bin/true")
        #expect(registrar.registered == [bundle.plainPath])
    }

    @Test func revealOpensTheLauncherFolderThroughTheInjectedOpener() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let opener = FakeFolderOpener()
        try revealLaunchers(layout: sandbox.layout, opener: opener)
        #expect(opener.opened == [sandbox.layout.launcherDir])
        #expect(FileManager.default.fileExists(atPath: sandbox.layout.launcherDir.plainPath))
    }

    @Test func quotesShellValues() {
        let script = LauncherBuilder.launchScript(profile: .default, hatsPath: "/Users/o'brien/bin/hats", hatsHome: "/h")
        #expect(script.contains(#"HATS='/Users/o'\''brien/bin/hats'"#))
    }

    @Test(.tags(.integration)) func launchScriptHasValidShellSyntax() throws {
        let script = LauncherBuilder.launchScript(profile: try ProfileName("work"), hatsPath: "/usr/bin/true", hatsHome: "/tmp/h h")
        let file = FileManager.default.temporaryDirectory.appending(path: "hats-launch-\(UUID().uuidString).sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-n", file.plainPath]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
