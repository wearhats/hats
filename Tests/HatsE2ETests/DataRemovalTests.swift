import Foundation
import Testing

@Suite("hats reset", .tags(.e2e))
struct ResetCommandTests {
    @Test func dryRunChangesNothing() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["reset", "work", "--dry-run"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "Would move \(sandbox.profileDir("work"))/desktop to the Trash.\n", "\(result)")
        #expect(try sandbox.snapshot() == before)
    }

    @Test func withoutATerminalItNeedsYes() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["reset", "work"])

        #expect(result.exit == 64, "\(result)")
        #expect(result.stderr.contains("pass --yes"), "\(result)")
        #expect(try sandbox.snapshot() == before)
    }

    @Test func yesMovesDesktopDataAwayAndRecreatesItEmpty() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let dir = sandbox.profileDir("work")

        let result = try sandbox.hats(["reset", "work", "--yes"])

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.trashed() == ["\(dir)/desktop"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: "\(dir)/desktop").isEmpty)
        #expect(try sandbox.permissions("\(dir)/desktop") == 0o700)
        #expect(sandbox.exists("\(dir)/code/.claude.json"))
        #expect(sandbox.exists(sandbox.launcher("Work")))
        #expect(try sandbox.events("register").count == 1)
        #expect(try sandbox.events("launch").isEmpty)
    }

    @Test func codeMovesAnOwnedCodeDirToo() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let dir = sandbox.profileDir("work")

        let result = try sandbox.hats(["reset", "work", "--code", "--yes"])

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.trashed() == ["\(dir)/desktop", "\(dir)/code"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: "\(dir)/code").isEmpty)
    }

    @Test func codeRefusesAnAdoptedDir() throws {
        let sandbox = try E2ESandbox()
        let adopted = "\(sandbox.root)/adopted"
        try sandbox.addProfile("work", adopting: adopted)

        let result = try sandbox.hats(["reset", "work", "--code", "--yes"])

        #expect(result.exit == 64, "\(result)")
        #expect(result.stderr.contains("which hats never deletes"), "\(result)")
        #expect(sandbox.exists("\(adopted)/.claude.json"))
        #expect(try sandbox.trashed().isEmpty)
    }

    @Test func openLaunchesAfterwards() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")

        let result = try sandbox.hats(["reset", "work", "--yes", "--open"], environment: try sandbox.withClaudeApp)

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.events("launch").count == 1)
        #expect(result.stdout.contains("Sign in inside the new window."), "\(result)")
    }
}

@Suite("hats rm", .tags(.e2e))
struct RemoveCommandTests {
    @Test func keepsDataAndRemovesTheLauncherAndItsCopies() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work", "--desktop"]).exit == 0)
        let copy = "\(sandbox.home)/Desktop/Claude (Work).app"

        let result = try sandbox.hats(["rm", "work"])

        #expect(result.exit == 0, "\(result)")
        #expect(!sandbox.exists(sandbox.launcher("Work")))
        #expect(!sandbox.exists(copy))
        #expect(sandbox.exists("\(sandbox.profileDir("work"))/profile.json"))
        #expect(try sandbox.trashed().isEmpty)
        #expect(result.stdout.contains("Data kept in \(sandbox.profileDir("work"))"), "\(result)")
    }

    @Test func purgeMovesTheProfileToTheTrash() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        let dir = sandbox.profileDir("work")

        let result = try sandbox.hats(["rm", "work", "--purge", "--yes"])

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.trashed() == [dir])
        #expect(!sandbox.exists(dir))
        #expect(!sandbox.exists(sandbox.launcher("Work")))
        #expect(!result.stdout.contains("Keychain"), "\(result)")
    }

    @Test func purgeKeepsAnAdoptedDir() throws {
        let sandbox = try E2ESandbox()
        let adopted = "\(sandbox.root)/adopted"
        try sandbox.addProfile("work", adopting: adopted)
        try sandbox.seedKeychain([sandbox.keychainService(forConfigDir: adopted)])

        let result = try sandbox.hats(["rm", "work", "--purge", "--yes"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("Kept the adopted Claude Code dir \(adopted)."), "\(result)")
        #expect(!result.stdout.contains("Keychain"), "\(result)")
        #expect(sandbox.exists("\(adopted)/.claude.json"))
    }

    @Test func purgeMentionsALeftoverKeychainItemOnlyWhenThereIsOne() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        let service = sandbox.keychainService(forConfigDir: code)
        try sandbox.seedKeychain([service])

        let result = try sandbox.hats(["rm", "work", "--purge", "--yes"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("stays in your Keychain as '\(service)'"), "\(result)")
    }

    @Test func purgeWithoutATerminalNeedsYes() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["rm", "work", "--purge"])

        #expect(result.exit == 64, "\(result)")
        #expect(try sandbox.snapshot() == before)
    }

    @Test func purgeDryRunChangesNothing() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["rm", "work", "--purge", "--dry-run"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("Would move \(sandbox.profileDir("work")) to the Trash."), "\(result)")
        #expect(try sandbox.snapshot() == before)
    }

    @Test func allSparesDefault() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        #expect(try sandbox.hats(["add", "other"]).exit == 0)

        let result = try sandbox.hats(["rm", "--all", "--purge", "--yes"])

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.trashed().sorted() == [sandbox.profileDir("other"), sandbox.profileDir("work")])
        let rows = try sandbox.json(try sandbox.hats(["ls", "--json"]))
        #expect(rows.map { $0["name"] as? String } == ["default"])
    }

    @Test func allRemovesTheApplicationsLink() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        #expect(try sandbox.hats(["launcher", "link"]).exit == 0)

        let dryRun = try sandbox.hats(["rm", "--all", "--dry-run"])

        #expect(dryRun.stdout.contains("Would remove the link \(sandbox.applicationsLink)."), "\(dryRun)")
        #expect(sandbox.linkDestination(sandbox.applicationsLink) == sandbox.launcherDir)

        let result = try sandbox.hats(["rm", "--all"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("Removed the link \(sandbox.applicationsLink)."), "\(result)")
        #expect(sandbox.linkDestination(sandbox.applicationsLink) == nil)
    }

    @Test func allLeavesAnotherUsersApplicationsLink() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        let theirs = "\(sandbox.root)/other-user/Applications/Hats"
        try FileManager.default.createSymbolicLink(atPath: sandbox.applicationsLink, withDestinationPath: theirs)
        #expect(try sandbox.hats(["add", "work"]).exit == 0)

        let result = try sandbox.hats(["rm", "--all"])

        #expect(result.exit == 0, "\(result)")
        #expect(sandbox.linkDestination(sandbox.applicationsLink) == theirs)
    }

    @Test func removingTwiceIsFineUntilTheDataIsGone() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)

        #expect(try sandbox.hats(["rm", "work"]).exit == 0)
        #expect(try sandbox.hats(["rm", "work"]).exit == 0)
        #expect(try sandbox.hats(["rm", "work", "--purge", "--yes"]).exit == 0)

        let result = try sandbox.hats(["rm", "work"])
        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("no profile named 'work'"), "\(result)")
    }
}
