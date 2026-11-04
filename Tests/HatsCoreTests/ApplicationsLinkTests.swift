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

    @Test func refusesAnotherAccountsLink() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let theirs = try sandbox.makeDirectory("other-user/Applications/Hats").plainPath
        try FileManager.default.createSymbolicLink(atPath: sandbox.applicationsLink.url.plainPath, withDestinationPath: theirs)
        let link = sandbox.applicationsLink(accountID: Sandbox.otherAccount)

        let error = try #require(throws: HatsError.self) { try link.link() }

        #expect(error.kind == .conflict)
        #expect(error.message.contains(theirs), "\(error)")
        #expect(try destination(of: link) == theirs)
        #expect(link.state() == .foreign(destination: theirs))
    }

    /// Who made the link decides whose it is, not where it points.
    @Test func anotherAccountsLinkIntoThisHomeIsStillTheirs() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let old = try sandbox.makeDirectory("home/Applications/Old").plainPath
        try FileManager.default.createSymbolicLink(atPath: sandbox.applicationsLink.url.plainPath, withDestinationPath: old)
        let link = sandbox.applicationsLink(accountID: Sandbox.otherAccount)

        #expect(link.state() == .foreign(destination: old))
        let error = try #require(throws: HatsError.self) { try link.unlink() }
        #expect(error.kind == .conflict)
        #expect(try destination(of: link) == old)
    }

    /// The link an admin makes for a standard account belongs to the admin, and
    /// it still serves this account's launchers.
    @Test func aLinkAnotherAccountMadeToThisLauncherDirIsOurs() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.applicationsLink.link()

        #expect(sandbox.applicationsLink(accountID: Sandbox.otherAccount).state() == .ours(dangling: false))
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
        #expect(throws: HatsError.self) { try link.unlink() }
        #expect(try String(contentsOf: keep, encoding: .utf8) == "mine")
    }

    /// Left behind after the launcher dir moved, such as by a new `HATS_LAUNCHER_DIR`.
    @Test func refusesAStaleLinkOfThisAccount() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        let old = sandbox.layout.home.appending(path: "Applications/Old").plainPath
        try FileManager.default.createSymbolicLink(atPath: link.url.plainPath, withDestinationPath: old)

        let error = try #require(throws: HatsError.self) { try link.link() }

        #expect(error.kind == .conflict)
        #expect(error.hint?.contains("hats launcher unlink") == true, "\(error)")
        #expect(try destination(of: link) == old)
        #expect(link.state() == .stale(destination: old))
    }

    /// A launcher dir outside the home folder, such as on another volume, is still
    /// this account's.
    @Test func unlinkRemovesAStaleLinkOfThisAccountWhereverItPoints() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        let old = try sandbox.makeDirectory("Volumes/Data/launchers").plainPath
        try FileManager.default.createSymbolicLink(atPath: link.url.plainPath, withDestinationPath: old)

        #expect(link.state() == .stale(destination: old))
        #expect(try link.unlink() == .removed)

        #expect(link.state() == .absent)
        #expect(FileManager.default.fileExists(atPath: old), "unlink removes only the link")
    }

    @Test func anOldLinkStaysVisibleOnceTheLauncherDirMovesIntoTheApplicationsDir() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.applicationsLink.link()
        var environment = sandbox.environment
        environment["HATS_LAUNCHER_DIR"] = sandbox.applicationsDir.appending(path: "HatsLaunchers").plainPath
        let link = sandbox.applicationsLink(accountID: geteuid(), layout: Layout(environment: environment))
        let old = sandbox.layout.launcherDir.plainPath

        #expect(link.state() == .stale(destination: old))
        #expect(try link.unlink() == .removed)

        #expect(link.state() == .notNeeded)
        #expect(FileManager.default.fileExists(atPath: old))
    }

    /// `sudo` keeps HOME on macOS, so hats as root would make the launcher dir
    /// in this home owned by root.
    @Test func refusesToLinkAsAnAccountThatDoesNotOwnTheHome() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink(accountID: Sandbox.otherAccount)

        let error = try #require(throws: HatsError.self) { try link.link() }

        #expect(error.kind == .environment, "\(error)")
        #expect(error.hint?.contains("without sudo") == true, "\(error)")
        #expect(link.state() == .absent)
        #expect(!FileManager.default.fileExists(atPath: sandbox.layout.launcherDir.plainPath), "a refusal writes nothing")
    }

    /// Root writes anywhere, and the Linux job runs its container as root.
    @Test(.enabled(if: geteuid() != 0))
    func anUnwritableApplicationsDirNeedsAnAdmin() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let link = sandbox.applicationsLink
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sandbox.applicationsDir.plainPath)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sandbox.applicationsDir.plainPath) }

        let error = try #require(throws: HatsError.self) { try link.link() }

        #expect(error.message.contains("admin"), "\(error)")
        let hint = try #require(error.hint)
        #expect(hint.contains("sudo ln -s '\(sandbox.layout.launcherDir.plainPath)' '\(link.url.plainPath)'"), "\(hint)")
        #expect(!hint.contains("sudo hats"), "hats as root would write this home as root")
        #expect(link.state() == .absent)
        #expect(
            FileManager.default.fileExists(atPath: sandbox.layout.launcherDir.plainPath),
            "the link an admin makes from the hint must not dangle")
    }

    @Test func aLauncherDirInsideTheApplicationsDirNeedsNoLink() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        var environment = sandbox.environment
        environment["HATS_LAUNCHER_DIR"] = sandbox.applicationsDir.appending(path: "Hats").plainPath
        let link = sandbox.applicationsLink(accountID: geteuid(), layout: Layout(environment: environment))

        #expect(link.state() == .notNeeded)
        #expect(try link.link() == .notNeeded)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.applicationsDir.plainPath).isEmpty)
    }

    /// A missing launcher dir must compare like its existing parent, however the
    /// path is spelled, as with `/private/var` and `/var` on macOS.
    @Test func aMissingLauncherDirReachedThroughASymlinkStillNeedsNoLink() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let alias = sandbox.root.appending(path: "alias").plainPath
        try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: sandbox.applicationsDir.plainPath)
        var environment = sandbox.environment
        environment["HATS_LAUNCHER_DIR"] = alias + "/Hats"
        let link = sandbox.applicationsLink(accountID: geteuid(), layout: Layout(environment: environment))

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

    @Test func unlinkLeavesAnotherAccountsLink() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let theirs = "/Users/someone-else/Applications/Hats"
        try FileManager.default.createSymbolicLink(atPath: sandbox.applicationsLink.url.plainPath, withDestinationPath: theirs)
        let link = sandbox.applicationsLink(accountID: Sandbox.otherAccount)

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

    /// `launcher rebuild` alone does nothing without a profile, and `launcher link`
    /// re-creates the launcher dir.
    @Test func warnsWhenOurLinkDangles() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.applicationsLink.link()
        try FileManager.default.removeItem(at: sandbox.layout.launcherDir)

        let finding = try #require(sandbox.doctor().run().first { $0.check == "applications-link" })

        #expect(finding.level == .warn, "\(finding)")
        #expect(finding.message.contains("missing"), "\(finding)")
        #expect(finding.hint?.contains("hats launcher link") == true, "\(finding)")
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
        #expect(finding.hint?.contains("hats launcher unlink") == true, "\(finding)")
    }

    @Test func warnsAboutAnOldLinkOnceTheLauncherDirMovesIntoTheApplicationsDir() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try sandbox.applicationsLink.link()
        var environment = sandbox.environment
        environment["HATS_LAUNCHER_DIR"] = sandbox.applicationsDir.appending(path: "HatsLaunchers").plainPath

        let findings = sandbox.doctor(layout: Layout(environment: environment)).run()

        let finding = try #require(findings.first { $0.check == "applications-link" })
        #expect(finding.level == .warn, "\(finding)")
        #expect(finding.message.contains(sandbox.layout.launcherDir.plainPath), "\(finding)")
    }

    @Test func leavesAnotherAccountsLinkAlone() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try FileManager.default.createSymbolicLink(
            atPath: sandbox.applicationsLink.url.plainPath, withDestinationPath: "/Users/someone-else/Applications/Hats")

        #expect(!sandbox.doctor(accountID: Sandbox.otherAccount).run().contains { $0.check == "applications-link" })
    }
}
