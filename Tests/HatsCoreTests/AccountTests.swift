import Foundation
import Testing
@testable import HatsCore

@Suite struct AccountProbeTests {
    @Test func reportsNeverOpenedForAFreshProfile() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (profile, _) = try sandbox.store.create(ProfileName("work"))
        let info = AccountProbe(layout: sandbox.layout).info(for: profile)
        #expect(info == AccountInfo(desktop: .neverOpened))
        #expect(info.accountID == nil)
    }

    @Test func readsIdentifiersButNotTokens() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (profile, _) = try sandbox.store.create(ProfileName("work"))
        try writeJSON(
            ["oauth:tokenCacheV2": "secret", "lastKnownAccountUuid": "acct-1"], to: profile.desktopDir.appending(path: "config.json"))
        try writeJSON(
            ["oauthAccount": ["accountUuid": "acct-1", "emailAddress": "me@work.example", "organizationName": "Work Inc"]],
            to: profile.codeDir.appending(path: ".claude.json"))

        let info = AccountProbe(layout: sandbox.layout).info(for: profile)
        #expect(info.desktop == .signedIn)
        #expect(info.desktopAccountID == "acct-1")
        #expect(info.codeEmail == "me@work.example")
        #expect(info.codeOrganization == "Work Inc")
        #expect(!info.isSplit)
        let encoded = String(decoding: try JSONEncoder().encode(info), as: UTF8.self)
        #expect(!encoded.contains("secret"))
    }

    @Test func detectsDesktopAndCodeOnDifferentAccounts() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (profile, _) = try sandbox.store.create(ProfileName("work"))
        try writeJSON(["oauth:tokenCache": "x", "lastKnownAccountUuid": "acct-1"], to: profile.desktopDir.appending(path: "config.json"))
        try writeJSON(["oauthAccount": ["accountUuid": "acct-2"]], to: profile.codeDir.appending(path: ".claude.json"))
        #expect(AccountProbe(layout: sandbox.layout).info(for: profile).isSplit)
    }

    @Test func signedOutDesktopKeepsItsLastAccountButIsNotSplit() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (profile, _) = try sandbox.store.create(ProfileName("work"))
        try writeJSON(["lastKnownAccountUuid": "acct-1"], to: profile.desktopDir.appending(path: "config.json"))
        try writeJSON(["oauthAccount": ["accountUuid": "acct-2"]], to: profile.codeDir.appending(path: ".claude.json"))
        let info = AccountProbe(layout: sandbox.layout).info(for: profile)
        #expect(info.desktop == .signedOut)
        #expect(!info.isSplit)
        #expect(info.accountID == "acct-2")
    }

    @Test func defaultProfileReadsClaudeJSONFromHome() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        try writeJSON(["oauthAccount": ["accountUuid": "acct-home"]], to: sandbox.layout.home.appending(path: ".claude.json"))
        #expect(AccountProbe(layout: sandbox.layout).info(for: sandbox.store.defaultProfile).codeAccountID == "acct-home")
    }

    @Test func unreadableDesktopConfigIsUnknown() throws {
        let sandbox = try Sandbox(); defer { sandbox.cleanUp() }
        let (profile, _) = try sandbox.store.create(ProfileName("work"))
        try Data("{not json".utf8).write(to: profile.desktopDir.appending(path: "config.json"))
        #expect(AccountProbe(layout: sandbox.layout).info(for: profile).desktop == .unknown)
    }
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: object).write(to: url)
}
