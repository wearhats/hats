import Foundation
import Testing

@testable import HatsCore

@Suite struct SemanticVersionTests {
    @Test func comparesNumerically() throws {
        #expect(try #require(SemanticVersion("0.10.0")) > #require(SemanticVersion("0.9.1")))
        #expect(SemanticVersion("v1.2.3") == SemanticVersion("1.2.3"))
    }

    @Test func rejectsPrereleasesAndJunk() {
        #expect(SemanticVersion("0.1.0-dev") == nil)
        #expect(SemanticVersion("1.2") == nil)
        #expect(SemanticVersion("latest") == nil)
    }
}

@Suite struct UpdateCheckTests {
    let start = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func runsOnlyForReleaseBuildsInAnInteractiveTerminal() {
        #expect(UpdateCheck.isEnabled(currentVersion: "0.1.0", environment: [:], stderrIsTerminal: true))
        #expect(!UpdateCheck.isEnabled(currentVersion: "0.1.0", environment: [:], stderrIsTerminal: false))
        #expect(!UpdateCheck.isEnabled(currentVersion: "0.1.0-dev", environment: [:], stderrIsTerminal: true))
        #expect(!UpdateCheck.isEnabled(currentVersion: "0.1.0", environment: ["CI": "true"], stderrIsTerminal: true))
        #expect(!UpdateCheck.isEnabled(currentVersion: "0.1.0", environment: ["HATS_NO_UPDATE_CHECK": "1"], stderrIsTerminal: true))
        #expect(UpdateCheck.isEnabled(currentVersion: "0.1.0", environment: ["HATS_NO_UPDATE_CHECK": ""], stderrIsTerminal: true))
    }

    @Test func checksAtMostOncePerInterval() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let feed = FakeReleaseFeed(latest: "v0.2.0")
        #expect(check(sandbox, feed, at: start).isDue())

        await check(sandbox, feed, at: start).refresh()
        #expect(feed.requests == 1)
        #expect(!check(sandbox, feed, at: start.addingTimeInterval(UpdateCheck.interval - 60)).isDue())
        #expect(check(sandbox, feed, at: start.addingTimeInterval(UpdateCheck.interval + 60)).isDue())
    }

    @Test func noticeNamesTheNewVersionAndTheUpgradeCommand() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        await check(sandbox, FakeReleaseFeed(latest: "v0.2.0"), at: start).refresh()

        let notice = try #require(
            check(sandbox, FakeReleaseFeed(), at: start).notice(currentVersion: "0.1.0", channel: .homebrew, home: "/Users/alice"))
        #expect(notice.message == "A new release of hats is available: 0.1.0 → 0.2.0")
        #expect(notice.upgradeCommand == "brew upgrade hats")
        #expect(notice.releaseURL == "https://github.com/wearhats/hats/releases/tag/v0.2.0")
    }

    @Test func noNoticeWhenUpToDateOrAhead() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        await check(sandbox, FakeReleaseFeed(latest: "v0.2.0"), at: start).refresh()
        let later = check(sandbox, FakeReleaseFeed(), at: start)
        #expect(later.notice(currentVersion: "0.2.0", channel: .homebrew, home: "/h") == nil)
        #expect(later.notice(currentVersion: "0.3.0", channel: .homebrew, home: "/h") == nil)
    }

    @Test func aFailedRequestKeepsTheLastAnswerAndWaitsAFullInterval() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        await check(sandbox, FakeReleaseFeed(latest: "v0.2.0"), at: start).refresh()

        let offline = FakeReleaseFeed()
        let nextDay = start.addingTimeInterval(UpdateCheck.interval + 60)
        await check(sandbox, offline, at: nextDay).refresh()
        #expect(offline.requests == 1)
        #expect(!check(sandbox, offline, at: nextDay.addingTimeInterval(60)).isDue())
        #expect(check(sandbox, offline, at: nextDay).notice(currentVersion: "0.1.0", channel: .unknown, home: "/h") != nil)
    }

    @Test func anUnreadableStateFileIsDueAndShowsNothing() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try FileManager.default.createDirectory(at: sandbox.layout.hatsHome, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: sandbox.layout.updateCheckState)
        let check = check(sandbox, FakeReleaseFeed(), at: start)
        #expect(check.isDue())
        #expect(check.notice(currentVersion: "0.1.0", channel: .homebrew, home: "/h") == nil)
    }

    @Test func aClockSetBackDoesNotSilenceChecks() async throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        await check(sandbox, FakeReleaseFeed(latest: "v0.2.0"), at: start).refresh()
        #expect(check(sandbox, FakeReleaseFeed(), at: start.addingTimeInterval(-3600)).isDue())
    }

    private func check(_ sandbox: Sandbox, _ feed: FakeReleaseFeed, at date: Date) -> UpdateCheck {
        UpdateCheck(layout: sandbox.layout, feed: feed, now: { date })
    }
}
