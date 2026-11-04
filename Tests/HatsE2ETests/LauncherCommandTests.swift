import Foundation
import Testing

@Suite("hats launcher", .tags(.e2e))
struct LauncherCommandTests {
    @Test func rebuildRepointsEveryLauncherWhenPathChanges() throws {
        let sandbox = try E2ESandbox()
        let first = try sandbox.hatsOnPath(directory: "first")
        let second = try sandbox.hatsOnPath(directory: "second")
        #expect(try sandbox.hats(["add", "work"], environment: first.environment).exit == 0)
        #expect(try sandbox.hats(["add", "other"], environment: first.environment).exit == 0)

        let result = try sandbox.hats(["launcher", "rebuild"], environment: second.environment)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.split(separator: "\n").count == 2, "\(result)")
        for label in ["Work", "Other"] {
            #expect(try sandbox.marker(in: sandbox.launcher(label))["hatsPath"] as? String == second.path)
        }
        #expect(try sandbox.events("register").count == 4)
    }

    @Test func rebuildByNameTouchesOnlyThatProfile() throws {
        let sandbox = try E2ESandbox()
        let first = try sandbox.hatsOnPath(directory: "first")
        let second = try sandbox.hatsOnPath(directory: "second")
        #expect(try sandbox.hats(["add", "work"], environment: first.environment).exit == 0)
        #expect(try sandbox.hats(["add", "other"], environment: first.environment).exit == 0)

        let result = try sandbox.hats(["launcher", "rebuild", "work"], environment: second.environment)

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.marker(in: sandbox.launcher("Work"))["hatsPath"] as? String == second.path)
        #expect(try sandbox.marker(in: sandbox.launcher("Other"))["hatsPath"] as? String == first.path)
    }

    @Test func rebuildRefreshesRecordedCopies() throws {
        let sandbox = try E2ESandbox()
        let first = try sandbox.hatsOnPath(directory: "first")
        let second = try sandbox.hatsOnPath(directory: "second")
        #expect(try sandbox.hats(["add", "work", "--desktop"], environment: first.environment).exit == 0)
        let copy = "\(sandbox.home)/Desktop/Claude (Work).app"

        let result = try sandbox.hats(["launcher", "rebuild", "work"], environment: second.environment)

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.marker(in: copy)["hatsPath"] as? String == second.path)
        #expect(try sandbox.marker(in: sandbox.launcher("Work"))["copies"] as? [String] == [copy])
    }

    @Test func copyDefaultsToHomeDesktopAndIsRecorded() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        let copy = "\(sandbox.home)/Desktop/Claude (Work).app"

        let result = try sandbox.hats(["launcher", "copy", "work"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "Copied to \(copy)\n", "\(result)")
        #expect(sandbox.exists("\(copy)/Contents/MacOS/launch"))
        #expect(try sandbox.marker(in: sandbox.launcher("Work"))["copies"] as? [String] == [copy])
        #expect(try sandbox.marker(in: copy)["copies"] == nil)
    }

    @Test func copyToAFolderRecordsBothAndARerunReplaces() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work", "--desktop"]).exit == 0)
        let folder = "\(sandbox.root)/folder"
        let copy = "\(folder)/Claude (Work).app"

        #expect(try sandbox.hats(["launcher", "copy", "work", "--to", folder]).exit == 0)
        try sandbox.write("stale", to: "\(copy)/stale-file")
        let result = try sandbox.hats(["launcher", "copy", "work", "--to", folder])

        #expect(result.exit == 0, "\(result)")
        #expect(!sandbox.exists("\(copy)/stale-file"))
        let copies = try sandbox.marker(in: sandbox.launcher("Work"))["copies"] as? [String]
        #expect(copies == ["\(sandbox.home)/Desktop/Claude (Work).app", copy])
    }

    @Test func aDestinationOwnedByAnotherProfileIsRefused() throws {
        let sandbox = try E2ESandbox()
        let folder = "\(sandbox.root)/folder"
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        #expect(try sandbox.hats(["launcher", "copy", "work", "--to", folder]).exit == 0)
        #expect(try sandbox.hats(["add", "work", "--label", "Acme"]).exit == 0)
        #expect(try sandbox.hats(["add", "other", "--label", "Work"]).exit == 0)
        let staleName = "\(folder)/Claude (Acme).app"
        #expect(sandbox.exists(staleName))
        #expect(try sandbox.hats(["add", "other", "--label", "Acme"]).exit == 1)

        try FileManager.default.moveItem(atPath: staleName, toPath: "\(folder)/Claude (Work).app")

        let result = try sandbox.hats(["launcher", "copy", "other", "--to", folder])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("is the launcher of profile 'work'"), "\(result)")
    }

    @Test func revealCreatesTheFolderAndAsksFinderToShowIt() throws {
        let sandbox = try E2ESandbox()
        #expect(!sandbox.exists(sandbox.launcherDir))

        let result = try sandbox.hats(["launcher", "reveal"])

        #expect(result.exit == 0, "\(result)")
        #expect(sandbox.exists(sandbox.launcherDir))
        #expect(try sandbox.events("reveal").map { $0["path"] as? String } == [sandbox.launcherDir])
    }

    @Test func linkShowsTheLaunchersInTheApplicationsDirAndUnlinkTakesItAway() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)

        let linked = try sandbox.hats(["launcher", "link"])

        #expect(linked.exit == 0, "\(linked)")
        #expect(linked.stdout.contains("Linked \(sandbox.applicationsLink) to \(sandbox.launcherDir)."), "\(linked)")
        #expect(sandbox.linkDestination(sandbox.applicationsLink) == sandbox.launcherDir)
        #expect(sandbox.exists("\(sandbox.applicationsLink)/Claude (Work).app/Contents/MacOS/launch"))

        let again = try sandbox.hats(["launcher", "link"])

        #expect(again.exit == 0, "\(again)")
        #expect(again.stdout.contains("already links to \(sandbox.launcherDir)"), "\(again)")

        let unlinked = try sandbox.hats(["launcher", "unlink"])

        #expect(unlinked.exit == 0, "\(unlinked)")
        #expect(unlinked.stdout == "Removed the link \(sandbox.applicationsLink).\n", "\(unlinked)")
        #expect(sandbox.linkDestination(sandbox.applicationsLink) == nil)
        #expect(sandbox.exists("\(sandbox.launcher("Work"))/Contents/MacOS/launch"), "unlink removes only the link")
    }

    @Test func linkAndUnlinkLeaveAnotherUsersLinkAlone() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        let theirs = "\(sandbox.root)/other-user/Applications/Hats"
        try sandbox.makeDirectory(theirs)
        try FileManager.default.createSymbolicLink(atPath: sandbox.applicationsLink, withDestinationPath: theirs)
        try sandbox.actAsAnotherAccount()
        let before = try sandbox.snapshot()

        for command in ["link", "unlink"] {
            let result = try sandbox.hats(["launcher", command])

            #expect(result.exit == 1, "\(command): \(result)")
            #expect(result.stderr.contains("links to \(theirs)"), "\(command): \(result)")
            #expect(try sandbox.snapshot() == before, "\(command): \(result)")
        }
    }

    @Test func unlinkRemovesThisAccountsOldLinkWhereverItPoints() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        let old = "\(sandbox.root)/Volumes/Data/launchers"
        try sandbox.makeDirectory(old)
        try FileManager.default.createSymbolicLink(atPath: sandbox.applicationsLink, withDestinationPath: old)

        let linked = try sandbox.hats(["launcher", "link"])

        #expect(linked.exit == 1, "\(linked)")
        #expect(linked.stderr.contains("hats launcher unlink"), "\(linked)")

        let unlinked = try sandbox.hats(["launcher", "unlink"])

        #expect(unlinked.exit == 0, "\(unlinked)")
        #expect(sandbox.linkDestination(sandbox.applicationsLink) == nil)
        #expect(sandbox.exists(old))
    }

    /// `sudo` keeps HOME, so hats as root would leave root-owned dirs in this home.
    @Test func linkRefusesToRunAsAnotherAccountThanTheHomeOwner() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        try sandbox.actAsAnotherAccount()
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["launcher", "link"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("without sudo"), "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }

    /// Reached through the link, the launcher dir looks like any other folder.
    @Test func copyToTheLinkKeepsTheLauncher() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        #expect(try sandbox.hats(["launcher", "link"]).exit == 0)

        let result = try sandbox.hats(["launcher", "copy", "work", "--to", sandbox.applicationsLink])

        #expect(result.exit != 0, "\(result)")
        #expect(sandbox.exists("\(sandbox.launcher("Work"))/Contents/MacOS/launch"), "\(result)")
        #expect(try sandbox.marker(in: sandbox.launcher("Work"))["copies"] == nil, "\(result)")
    }

    @Test func linkWithALauncherDirInsideTheApplicationsDirSaysNoLinkIsNeeded() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["launcher", "link"], environment: ["HATS_LAUNCHER_DIR": sandbox.applicationsLink])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("No link needed"), "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }
}

/// The generated script itself, run the way Launch Services runs it: from
/// launchd's environment, which has no `HATS_HOME`.
@Suite("Launcher script", .tags(.e2e))
struct LauncherScriptTests {
    @Test func reachesOpenAgainstThePinnedRoot() throws {
        let sandbox = try E2ESandbox()
        let code = "\(sandbox.profileDir("work"))/code"
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        let app = try sandbox.makeApp()

        let result = try sandbox.guarded(
            "/bin/sh", ["\(sandbox.launcher("Work"))/Contents/MacOS/launch"], environment: ["HATS_CLAUDE_APP": app], removing: ["HATS_HOME"]
        )

        #expect(result.exit == 0, "\(result)")
        let launch = try #require(try sandbox.events("launch").first, "\(result)")
        #expect(launch["arguments"] as? [String] == ["--user-data-dir=\(sandbox.profileDir("work"))/desktop"])
        #expect(launch["environment"] as? [String: String] == ["CLAUDE_CONFIG_DIR": code])
    }

    /// The script calls osascript by absolute path, and a test must never raise a
    /// real dialog, so the copy under test calls a shell function instead.
    @Test func withHatsGoneItExitsOneAndAsksForTheAlert() throws {
        let sandbox = try E2ESandbox()
        let onPath = try sandbox.hatsOnPath()
        #expect(try sandbox.hats(["add", "work"], environment: onPath.environment).exit == 0)
        try FileManager.default.removeItem(atPath: onPath.path)
        let alertLog = "\(sandbox.root)/alert.log"
        let script = try sandbox.read("\(sandbox.launcher("Work"))/Contents/MacOS/launch")
        #expect(script.contains("/usr/bin/osascript"))
        let copy = "\(sandbox.root)/launch-copy"
        let standIn = "alert_stand_in() { printf '%s\\n' \"$2\" > '\(alertLog)'; }\n"
        try sandbox.write(standIn + script.replacingOccurrences(of: "/usr/bin/osascript", with: "alert_stand_in"), to: copy)

        let result = try sandbox.guarded("/bin/sh", [copy], removing: ["HATS_HOME"])

        #expect(result.exit == 1, "\(result)")
        #expect(try sandbox.read(alertLog).contains("hats is not installed"))
        #expect(try sandbox.events("launch").isEmpty)
    }
}
