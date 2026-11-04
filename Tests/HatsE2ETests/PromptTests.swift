import Foundation
import Testing

@Suite("Prompts on a terminal", .tags(.e2e))
struct PromptTests {
    @Test(arguments: ["n", ""])
    func resetDeclinedChangesNothing(answer: String) throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        let before = try sandbox.snapshot()

        let result = try sandbox.hatsOnTerminal(["reset", "work"], steps: [PTYStep("Start 'work' fresh? [y/N]", send: answer)])

        #expect(result.exit == 0, "\(result)")
        #expect(result.transcript.contains("Nothing changed."), "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }

    @Test func resetConfirmedMovesTheData() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")

        let result = try sandbox.hatsOnTerminal(["reset", "work"], steps: [PTYStep("[y/N]", send: "y")])

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.trashed() == ["\(sandbox.profileDir("work"))/desktop"])
    }

    @Test func purgeConfirmedByTypingTheName() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)

        let result = try sandbox.hatsOnTerminal(
            ["rm", "work", "--purge"], steps: [PTYStep("Type the profile name to confirm:", send: "work")])

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.trashed() == [sandbox.profileDir("work")])
    }

    @Test func aWrongNameCancelsThePurge() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        let before = try sandbox.snapshot()

        let result = try sandbox.hatsOnTerminal(
            ["rm", "work", "--purge"], steps: [PTYStep("Type the profile name to confirm:", send: "wrong")])

        #expect(result.exit == 64, "\(result)")
        #expect(result.transcript.contains("confirmation did not match; nothing was deleted"), "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }

    @Test func dedupeDefaultsToYes() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        _ = try sandbox.startDesktop(profile: "work")
        let newer = try sandbox.startDesktop(profile: "work")

        let result = try sandbox.hatsOnTerminal(["dedupe"], steps: [PTYStep("Quit the extra instances? [Y/n]")])

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.events("terminate").map { $0["pid"] as? Int } == [Int(newer.pid)])
    }

    @Test func dedupeDeclinedQuitsNothing() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        _ = try sandbox.startDesktop(profile: "work")
        _ = try sandbox.startDesktop(profile: "work")

        let result = try sandbox.hatsOnTerminal(["dedupe"], steps: [PTYStep("[Y/n]", send: "n")])

        #expect(result.exit == 0, "\(result)")
        #expect(result.transcript.contains("Nothing changed."), "\(result)")
        #expect(try sandbox.events("terminate").isEmpty)
    }

    @Test func aTableIsStyledOnATerminalUnlessNoColorIsSet() throws {
        let sandbox = try E2ESandbox()

        let styled = try sandbox.hatsOnTerminal(["ls"], removing: ["NO_COLOR"])
        let plain = try sandbox.hatsOnTerminal(["ls"])

        #expect(styled.transcript.contains("\u{1B}[1mPROFILE"), "\(styled)")
        #expect(!plain.transcript.contains("\u{1B}["), "\(plain)")
    }

    /// A terminal is the one place the update check would run, and test mode must
    /// turn it off with nothing else doing so. The Seatbelt guard stops the request
    /// itself; this catches the check being attempted at all.
    @Test func testModeNeverChecksForUpdates() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hatsOnTerminal(["ls"])

        #expect(result.exit == 0, "\(result)")
        #expect(!sandbox.exists("\(sandbox.hatsHome)/update-check.json"), "\(result)")
    }
}

@Suite("hats setup", .tags(.e2e))
struct SetupCommandTests {
    @Test func adoptsWhatItFindsAddsAProfileAndPinsAndOpens() throws {
        let sandbox = try E2ESandbox()
        let adopted = "\(sandbox.home)/.claude-work"
        try sandbox.write(#"{"accessToken":"\#(sandbox.sentinel)"}"#, to: "\(adopted)/.claude.json")
        let adoptedBefore = try sandbox.read("\(adopted)/.claude.json")
        let app = try sandbox.makeApp()
        try sandbox.makeApplicationsDir()

        let result = try sandbox.hatsOnTerminal(
            ["setup"],
            steps: [
                PTYStep("Turn it into a profile? Its login and history stay as they are. [Y/n]"),
                PTYStep("Profile name [work]"),
                PTYStep("Add a profile for another account? [y/N]", send: "y"),
                PTYStep("Name for your other account", send: "personal"),
                PTYStep("Pin the new launcher(s) to the Dock? This restarts the Dock. [Y/n]"),
                PTYStep("Also show them in Finder's Applications folder? This adds a link at \(sandbox.applicationsLink). [Y/n]"),
                PTYStep("Also put a copy on the Desktop? [y/N]"),
                PTYStep("Open work, personal now to sign in? [Y/n]"),
            ],
            environment: ["HATS_CLAUDE_APP": app])

        #expect(result.exit == 0, "\(result)")
        #expect(result.transcript.contains("Found a Claude Code config dir you made yourself: \(adopted)"), "\(result)")
        for line in [
            "$ hats add work --code-dir '\(adopted)'", "$ hats add personal", "$ hats dock pin work personal", "$ hats launcher link",
            "$ hats open work", "$ hats open personal",
        ] {
            #expect(result.transcript.contains(line), "\(line)\n\(result)")
        }
        #expect(result.transcript.contains("Everyday commands:"), "\(result)")
        #expect(try sandbox.read("\(adopted)/.claude.json") == adoptedBefore)
        #expect(try FileManager.default.contentsOfDirectory(atPath: adopted) == [".claude.json"])
        #expect(try sandbox.metadata(ofProfile: "work")["externalCodeDir"] as? String == adopted)
        #expect(try sandbox.metadata(ofProfile: "personal")["externalCodeDir"] == nil)

        let tiles = try sandbox.dockTiles()
        #expect(tiles.count == 2, "\(tiles)")
        #expect(tiles.contains { $0.hasSuffix("Claude%20(Work).app/") }, "\(tiles)")
        #expect(tiles.contains { $0.hasSuffix("Claude%20(Personal).app/") }, "\(tiles)")
        #expect(try sandbox.events("dock-restart").count == 1)
        #expect(sandbox.linkDestination(sandbox.applicationsLink) == sandbox.launcherDir)

        let launches = try sandbox.events("launch")
        #expect(launches.allSatisfy { $0["app"] as? String == app })
        #expect(
            launches.map { $0["environment"] as? [String: String] } == [
                ["CLAUDE_CONFIG_DIR": adopted], ["CLAUDE_CONFIG_DIR": "\(sandbox.profileDir("personal"))/code"],
            ])
        #expect(!sandbox.exists("\(sandbox.home)/Desktop"), "the copy prompt was answered No")
    }

    @Test func aRerunOffersNothingNew() throws {
        let sandbox = try E2ESandbox()
        let adopted = "\(sandbox.home)/.claude-work"
        try sandbox.write("{}", to: "\(adopted)/.claude.json")
        #expect(try sandbox.hats(["add", "work", "--code-dir", adopted]).exit == 0)
        let before = try sandbox.snapshot()

        let result = try sandbox.hatsOnTerminal(["setup"], steps: [PTYStep("Add a profile for another account? [y/N]")])

        #expect(result.exit == 0, "\(result)")
        #expect(!result.transcript.contains("Found a Claude Code config dir"), "\(result)")
        #expect(result.transcript.contains("Everyday commands:"), "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }

    @Test func withNothingToAdoptItAsksForTheFirstProfile() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hatsOnTerminal(
            ["setup"],
            steps: [
                PTYStep("Name for your other account (for example personal, work, acme) [personal]"),
                PTYStep("Pin the new launcher(s) to the Dock? This restarts the Dock. [Y/n]", send: "n"),
                PTYStep("Also show them in Finder's Applications folder?", send: "n"),
                PTYStep("Also put a copy on the Desktop? [y/N]", send: "y"),
                PTYStep("Open personal now to sign in? [Y/n]", send: "n"),
            ])

        #expect(result.exit == 0, "\(result)")
        #expect(sandbox.exists("\(sandbox.profileDir("personal"))/profile.json"))
        #expect(sandbox.exists("\(sandbox.home)/Desktop/Claude (Personal).app"))
        #expect(try sandbox.dockTiles().isEmpty)
        #expect(try sandbox.events("launch").isEmpty)
    }

    @Test func theApplicationsQuestionIsSkippedWhenTheLinkIsAlreadyThere() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        #expect(try sandbox.hats(["launcher", "link"]).exit == 0)

        let result = try sandbox.hatsOnTerminal(
            ["setup"],
            steps: [
                PTYStep("Name for your other account", send: "personal"),
                PTYStep("Pin the new launcher(s)", send: "n"),
                PTYStep("Also put a copy on the Desktop?"),
                PTYStep("Open personal now to sign in?", send: "n"),
            ])

        #expect(result.exit == 0, "\(result)")
        #expect(!result.transcript.contains("Finder's Applications folder"), "\(result)")
        #expect(sandbox.linkDestination(sandbox.applicationsLink) == sandbox.launcherDir)
    }

    @Test func aLinkThatCannotBeMadeIsReportedAndSetupCarriesOn() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        let theirs = "\(sandbox.root)/other-user/Applications/Hats"
        try FileManager.default.createSymbolicLink(atPath: sandbox.applicationsLink, withDestinationPath: theirs)

        let result = try sandbox.hatsOnTerminal(
            ["setup"],
            steps: [
                PTYStep("Name for your other account", send: "personal"),
                PTYStep("Pin the new launcher(s)", send: "n"),
                PTYStep("Also show them in Finder's Applications folder?"),
                PTYStep("Also put a copy on the Desktop?"),
                PTYStep("Open personal now to sign in?", send: "n"),
            ])

        #expect(result.exit == 0, "\(result)")
        #expect(result.transcript.contains("links to \(theirs)"), "\(result)")
        #expect(result.transcript.contains("Everyday commands:"), "\(result)")
        #expect(sandbox.linkDestination(sandbox.applicationsLink) == theirs)
    }

    @Test func aDeclinedCandidateIsLeftAlone() throws {
        let sandbox = try E2ESandbox()
        let adopted = "\(sandbox.home)/.claude-work"
        try sandbox.write("{}", to: "\(adopted)/.claude.json")
        let candidateBefore = try sandbox.snapshot().filter { $0.key.hasPrefix("home/.claude-work") }

        let result = try sandbox.hatsOnTerminal(
            ["setup"],
            steps: [
                PTYStep("Turn it into a profile?", send: "n"),
                PTYStep("Name for your other account", send: "personal"),
                PTYStep("Pin the new launcher(s)", send: "n"),
                PTYStep("Also show them in Finder's Applications folder?", send: "n"),
                PTYStep("Also put a copy on the Desktop?"),
                PTYStep("Open personal now to sign in?", send: "n"),
            ])

        #expect(result.exit == 0, "\(result)")
        #expect(!sandbox.exists(sandbox.profileDir("work")), "\(result)")
        #expect(try sandbox.metadata(ofProfile: "personal")["externalCodeDir"] == nil, "\(result)")
        #expect(try sandbox.snapshot().filter { $0.key.hasPrefix("home/.claude-work") } == candidateBefore, "\(result)")
    }

    @Test func testModeRefusesToAdoptADirOutside() throws {
        let sandbox = try E2ESandbox()
        let outside = FileManager.default.temporaryDirectory.path(percentEncoded: false) + "hats-e2e-outside-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: outside) }
        try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: URL(filePath: "\(outside)/settings.json"))
        try FileManager.default.createSymbolicLink(atPath: "\(sandbox.home)/.claude-escape", withDestinationPath: outside)

        let result = try sandbox.hatsOnTerminal(
            ["setup"], steps: [PTYStep("Turn it into a profile?"), PTYStep("Profile name [escape]")])

        #expect(result.exit == 1, "\(result)")
        #expect(result.transcript.contains("the dir to adopt is outside"), "\(result)")
        #expect(!sandbox.exists(sandbox.profileDir("escape")), "\(result)")
    }
}
