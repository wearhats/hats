import Foundation
import Testing
@testable import HatsCore

@Suite struct ApplicationsLinkTests {
    @Test func linkPointsTheApplicationsDirAtTheLauncherDir() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink

        #expect(try link.link() == .created)

        #expect(try destination(of: link) == sandbox.layout.launcherDir.plainPath)
        #expect(FileManager.default.fileExists(atPath: sandbox.layout.launcherDir.plainPath), "the link must not dangle")
        #expect(link.state() == .ours(dangling: false))
    }

    @Test func linkingTwiceLeavesTheLinkAsItIs() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        try link.link()

        #expect(try link.link() == .alreadyLinked)
        #expect(try destination(of: link) == sandbox.layout.launcherDir.plainPath)
    }

    @Test func refusesAnotherUsersLink() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        let theirs = try sandbox.makeDirectory("other-user/Applications/Hats").plainPath
        try FileManager.default.createSymbolicLink(atPath: link.url.plainPath, withDestinationPath: theirs)

        let error = try #require(throws: HatsError.self) { try link.link() }

        #expect(error.kind == .conflict)
        #expect(error.message.contains(theirs), "\(error)")
        #expect(try destination(of: link) == theirs)
        #expect(link.state() == .foreign(destination: theirs))
    }

    @Test func refusesARealFolder() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        try FileManager.default.createDirectory(at: link.url, withIntermediateDirectories: true)
        let keep = link.url.appending(path: "keep.txt")
        try Data("mine".utf8).write(to: keep)

        let error = try #require(throws: HatsError.self) { try link.link() }

        #expect(error.kind == .conflict)
        #expect(try String(contentsOf: keep, encoding: .utf8) == "mine")
        #expect(link.state() == .foreign(destination: nil))
    }

    /// Left behind after the launcher dir moved, such as by a new `HATS_LAUNCHER_DIR`.
    @Test func refusesAStaleLinkOfThisUser() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        let old = sandbox.layout.home.appending(path: "Applications/Old").plainPath
        try FileManager.default.createSymbolicLink(atPath: link.url.plainPath, withDestinationPath: old)

        let error = try #require(throws: HatsError.self) { try link.link() }

        #expect(error.kind == .conflict)
        #expect(error.hint?.contains("rm ") == true, "\(error)")
        #expect(try destination(of: link) == old)
        #expect(link.state() == .stale(destination: old))
    }

    /// Root writes anywhere, and the Linux job runs its container as root.
    @Test(.enabled(if: ProcessInfo.processInfo.userName != "root"))
    func anUnwritableApplicationsDirNeedsAnAdmin() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sandbox.applicationsDir.plainPath)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sandbox.applicationsDir.plainPath) }

        let error = try #require(throws: HatsError.self) { try link.link() }

        #expect(error.message.contains("admin"), "\(error)")
        let hint = try #require(error.hint)
        #expect(hint.contains("ln -s '\(sandbox.layout.launcherDir.plainPath)' '\(link.url.plainPath)'"), "\(hint)")
        #expect(!hint.contains("sudo"), "hats as root would use root's HOME")
        #expect(link.state() == .absent)
        #expect(!FileManager.default.fileExists(atPath: sandbox.layout.launcherDir.plainPath), "a refusal changes nothing")
    }

    @Test func aLauncherDirInsideTheApplicationsDirNeedsNoLink() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        var environment = sandbox.environment
        environment["HATS_LAUNCHER_DIR"] = sandbox.applicationsDir.appending(path: "Hats").plainPath
        let link = ApplicationsLink(layout: Layout(environment: environment), applicationsDir: sandbox.applicationsDir)

        #expect(link.state() == .notNeeded)
        #expect(try link.link() == .notNeeded)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.applicationsDir.plainPath).isEmpty)
    }

    @Test func unlinkRemovesOnlyTheLink() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        let bundle = try sandbox.launchers.build(for: try sandbox.store.create(ProfileName("work")).profile, hatsPath: "/usr/bin/true")
        try link.link()

        #expect(try link.unlink() == .removed)

        #expect(link.state() == .absent)
        #expect(FileManager.default.fileExists(atPath: bundle.plainPath))
    }

    @Test func unlinkRemovesALinkThatDangles() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        try link.link()
        try FileManager.default.removeItem(at: sandbox.layout.launcherDir)

        #expect(try link.unlink() == .removed)
        #expect(link.state() == .absent)
    }

    @Test func unlinkLeavesAnotherUsersLink() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        let theirs = "/Users/someone-else/Applications/Hats"
        try FileManager.default.createSymbolicLink(atPath: link.url.plainPath, withDestinationPath: theirs)

        let error = try #require(throws: HatsError.self) { try link.unlink() }

        #expect(error.kind == .conflict)
        #expect(try destination(of: link) == theirs)
    }

    @Test func unlinkWithNoLinkIsANoOp() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        #expect(try sandbox.applicationsLink.unlink() == .notLinked)
    }

    private func destination(of link: ApplicationsLink) throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: link.url.plainPath)
    }
}

@Suite struct ApplicationsLinkDoctorTests {
    @Test func saysNothingWithoutALink() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        #expect(!sandbox.doctor().run().contains { $0.check == "applications-link" })
    }

    @Test func reportsOurLink() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.applicationsLink.link()

        let finding = try #require(sandbox.doctor().run().first { $0.check == "applications-link" })

        #expect(finding.level == .ok, "\(finding)")
    }

    @Test func warnsWhenOurLinkDangles() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.applicationsLink.link()
        try FileManager.default.removeItem(at: sandbox.layout.launcherDir)

        let finding = try #require(sandbox.doctor().run().first { $0.check == "applications-link" })

        #expect(finding.level == .warn, "\(finding)")
        #expect(finding.message.contains("missing"), "\(finding)")
        #expect(finding.hint?.contains("hats launcher rebuild") == true, "\(finding)")
        #expect(finding.hint?.contains("hats launcher unlink") == true, "\(finding)")
    }

    @Test func warnsWhenTheLinkPointsAtAnOldLauncherDir() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        let old = try sandbox.makeDirectory("home/Applications/Old").plainPath
        try FileManager.default.createSymbolicLink(atPath: link.url.plainPath, withDestinationPath: old)

        let finding = try #require(sandbox.doctor().run().first { $0.check == "applications-link" })

        #expect(finding.level == .warn, "\(finding)")
        #expect(finding.message.contains(old), "\(finding)")
        #expect(finding.hint?.contains("hats launcher link") == true, "\(finding)")
    }

    @Test func leavesAnotherUsersLinkAlone() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try FileManager.default.createSymbolicLink(
            atPath: sandbox.applicationsLink.url.plainPath, withDestinationPath: "/Users/someone-else/Applications/Hats")

        #expect(!sandbox.doctor().run().contains { $0.check == "applications-link" })
    }
}
