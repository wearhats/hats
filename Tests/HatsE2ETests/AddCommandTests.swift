import Foundation
import Testing

@Suite("hats add", .tags(.e2e))
struct AddCommandTests {
    @Test func createsTheProfileItsDirsAndItsLauncher() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(["add", "work"])

        #expect(result.exit == 0, "\(result)")
        let dir = sandbox.profileDir("work")
        let bundle = sandbox.launcher("Work")
        #expect(result.stdout.hasPrefix("Created profile 'work'.\n"), "\(result)")
        #expect(result.stdout.contains("  launcher  \(bundle)\n"), "\(result)")
        let howToOpen = #"  open      Spotlight "Claude (Work)", hats dock pin work, or hats launcher reveal"#
        #expect(result.stdout.contains("  launcher  \(bundle)\n\(howToOpen)\n"), "\(result)")
        #expect(result.stdout.contains("  desktop   \(dir)/desktop\n"), "\(result)")
        #expect(result.stdout.contains("  code      \(dir)/code\n"), "\(result)")
        #expect(result.stdout.contains("Next:\n"), "\(result)")

        let metadata = try #require(
            try JSONSerialization.jsonObject(with: Data(sandbox.read("\(dir)/profile.json").utf8)) as? [String: Any])
        #expect(metadata["schemaVersion"] as? Int == 1)
        #expect(metadata["label"] as? String == "Work")
        #expect(metadata["icon"] as? String == "briefcase")
        #expect((metadata["color"] as? String)?.hasPrefix("#") == true)
        #expect(metadata["createdAt"] is String)
        #expect(metadata["externalCodeDir"] == nil)

        #expect(try sandbox.permissions("\(dir)/desktop") == 0o700)
        #expect(try sandbox.permissions("\(dir)/code") == 0o700)

        #expect(try sandbox.marker(in: bundle)["name"] as? String == "work")
        #expect(sandbox.exists("\(bundle)/Contents/Resources/AppIcon.icns"))
        #expect(sandbox.exists("\(bundle)/Contents/Info.plist"))
        #expect(try sandbox.permissions("\(bundle)/Contents/MacOS/launch") == 0o755)
        let registered = try sandbox.events("register").map { $0["path"] as? String }
        #expect(registered == [bundle])
    }

    @Test func theLauncherCallsTheHatsOnPathAndPinsTheDataRoot() throws {
        let sandbox = try E2ESandbox()
        let onPath = try sandbox.hatsOnPath()

        let result = try sandbox.hats(["add", "work"], environment: onPath.environment)

        #expect(result.exit == 0, "\(result)")
        let script = try sandbox.read("\(sandbox.launcher("Work"))/Contents/MacOS/launch")
        #expect(script.contains("export HATS_HOME='\(sandbox.hatsHome)'"), "\(script)")
        #expect(script.contains("HATS='\(onPath.path)'"), "\(script)")
        #expect(try sandbox.marker(in: sandbox.launcher("Work"))["hatsPath"] as? String == onPath.path)
    }

    @Test func aSecondRunKeepsTheData() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        let sentinelFile = "\(sandbox.profileDir("work"))/desktop/keep-me"
        try sandbox.write("kept", to: sentinelFile)
        let metadata = try sandbox.read("\(sandbox.profileDir("work"))/profile.json")

        let result = try sandbox.hats(["add", "work"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.hasPrefix("Profile 'work' already exists; launcher rebuilt.\n"), "\(result)")
        #expect(!result.stdout.contains("Next:"), "\(result)")
        #expect(try sandbox.read(sentinelFile) == "kept")
        #expect(try sandbox.read("\(sandbox.profileDir("work"))/profile.json") == metadata)
    }

    @Test func aNewLabelReplacesTheBundleAndMovesRecordedCopies() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work", "--desktop"]).exit == 0)
        let oldCopy = "\(sandbox.home)/Desktop/Claude (Work).app"
        #expect(sandbox.exists(oldCopy))

        let result = try sandbox.hats(["add", "work", "--label", "Acme"])

        #expect(result.exit == 0, "\(result)")
        let newCopy = "\(sandbox.home)/Desktop/Claude (Acme).app"
        #expect(!sandbox.exists(sandbox.launcher("Work")))
        #expect(sandbox.exists(sandbox.launcher("Acme")))
        #expect(!sandbox.exists(oldCopy))
        #expect(sandbox.exists(newCopy))
        #expect(try sandbox.marker(in: sandbox.launcher("Acme"))["copies"] as? [String] == [newCopy])
    }

    @Test func aForeignBundleAtTheLauncherPathIsLeftAlone() throws {
        let sandbox = try E2ESandbox()
        let foreign = "\(sandbox.launcher("Work"))/Contents/Info.plist"
        try sandbox.write("not hats", to: foreign)

        let result = try sandbox.hats(["add", "work"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("was not created by hats"), "\(result)")
        #expect(try sandbox.read(foreign) == "not hats")
        #expect(try sandbox.events("register").isEmpty)
    }

    @Test func adoptingADirCreatesNoCodeDirAndChangesNothingInIt() throws {
        let sandbox = try E2ESandbox()
        let adopted = "\(sandbox.root)/adopted"
        try sandbox.write("{}", to: "\(adopted)/settings.json")

        let result = try sandbox.hats(["add", "work", "--code-dir", adopted])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("  code      \(adopted) (adopted)\n"), "\(result)")
        #expect(!sandbox.exists("\(sandbox.profileDir("work"))/code"))
        #expect(try sandbox.read("\(adopted)/settings.json") == "{}")
        #expect(try FileManager.default.contentsOfDirectory(atPath: adopted) == ["settings.json"])
    }

    @Test func desktopPutsARecordedCopyInHomeDesktop() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(["add", "work", "--desktop"])

        #expect(result.exit == 0, "\(result)")
        let copy = "\(sandbox.home)/Desktop/Claude (Work).app"
        #expect(result.stdout.contains("  copy      \(copy)\n"), "\(result)")
        #expect(sandbox.exists(copy))
        #expect(try sandbox.marker(in: sandbox.launcher("Work"))["copies"] as? [String] == [copy])
    }

    @Test func pinWritesOneTileAndRestartsTheDockOnce() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(["add", "work", "--pin"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("Pinned Claude (Work) to the Dock."), "\(result)")
        #expect(try sandbox.dockTiles().count == 1)
        #expect(try sandbox.events("dock-write").count == 1)
        #expect(try sandbox.events("dock-restart").count == 1)
    }

    @Test func openLaunchesAndPrintsTheSignInGuidance() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(["add", "work", "--open"], environment: try sandbox.withClaudeApp)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("Launched Claude (Work), pid"), "\(result)")
        #expect(result.stdout.contains("Sign in inside the new window."), "\(result)")
        #expect(!result.stdout.contains("Next:"), "\(result)")
        #expect(try sandbox.events("launch").count == 1)
    }
}
