import Foundation
import Testing

@testable import HatsCore

@Suite struct InstallChannelTests {
    @Test func homebrewIsRecognizedByItsCellar() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let binary = try sandbox.makeExecutable("homebrew/Cellar/hats/0.1.0/bin/hats")
        #expect(InstallChannel.detect(executable: binary, layout: sandbox.layout) == .homebrew)
    }

    @Test func scriptIsRecognizedByAReceiptNamingThisBinary() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let binary = try sandbox.makeExecutable("home/.local/bin/hats")
        try sandbox.writeReceipt(#"{"installer":"install.sh","path":"\#(binary.plainPath)","version":"hats 0.1.0"}"#)
        #expect(
            InstallChannel.detect(executable: binary, layout: sandbox.layout)
                == .script(directory: binary.deletingLastPathComponent().plainPath))
    }

    @Test func aReceiptForAnotherBinaryDoesNotCount() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let binary = try sandbox.makeExecutable("src/.build/release/hats")
        try sandbox.writeReceipt(#"{"installer":"install.sh","path":"/elsewhere/hats"}"#)
        #expect(InstallChannel.detect(executable: binary, layout: sandbox.layout) == .unknown)
    }

    @Test func anUnreadableReceiptMeansUnknown() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let binary = try sandbox.makeExecutable("home/.local/bin/hats")
        try sandbox.writeReceipt("not json")
        #expect(InstallChannel.detect(executable: binary, layout: sandbox.layout) == .unknown)
    }

    @Test func upgradeCommandsMatchTheChannel() {
        #expect(InstallChannel.homebrew.upgradeCommand(home: "/Users/alice") == "brew upgrade hats")
        #expect(
            InstallChannel.script(directory: "/Users/alice/.local/bin").upgradeCommand(home: "/Users/alice")
                == "curl -fsSL https://wearhats.dev/install.sh | sh")
        #expect(
            InstallChannel.script(directory: "/opt/my tools").upgradeCommand(home: "/Users/alice")
                == "curl -fsSL https://wearhats.dev/install.sh | sh -s -- --dir '/opt/my tools'")
        #expect(InstallChannel.unknown.upgradeCommand(home: "/Users/alice") == nil)
    }
}

@Suite struct DoctorInstallTests {
    @Test func namesTheUpgradeCommandForTheChannel() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let binary = try sandbox.makeExecutable("homebrew/Cellar/hats/0.1.0/bin/hats")
        let install = HatsInstall(version: "0.1.0", executable: binary, launcherTarget: binary.plainPath)
        let findings = sandbox.doctor(install: install).run()
        #expect(
            findings.contains {
                $0.check == "install" && $0.level == .ok && $0.message.contains("Homebrew") && $0.message.contains("brew upgrade hats")
            })
    }

    @Test func warnsWhenALauncherCallsAnotherHatsBinary() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let old = try sandbox.makeExecutable("home/.local/bin/hats")
        let current = try sandbox.makeExecutable("homebrew/Cellar/hats/0.2.0/bin/hats")
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        try sandbox.launchers.build(for: work, hatsPath: old.plainPath)

        let install = HatsInstall(version: "0.2.0", executable: current, launcherTarget: current.plainPath)
        let findings = sandbox.doctor(install: install).run()
        #expect(
            findings.contains {
                $0.check == "profile:work" && $0.level == .warn && $0.message.contains(old.plainPath)
                    && $0.hint == "run: hats launcher rebuild"
            })
    }

    @Test func aLauncherCallingTheSameBinaryThroughASymlinkIsFine() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let binary = try sandbox.makeExecutable("homebrew/Cellar/hats/0.1.0/bin/hats")
        let link = sandbox.root.appending(path: "homebrew/bin/hats")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: binary)
        let (work, _) = try sandbox.store.create(ProfileName("work"))
        try sandbox.launchers.build(for: work, hatsPath: link.plainPath)

        let install = HatsInstall(version: "0.1.0", executable: binary, launcherTarget: link.plainPath)
        let findings = sandbox.doctor(install: install).run()
        #expect(findings.contains { $0.check == "profile:work" && $0.level == .ok })
    }
}
