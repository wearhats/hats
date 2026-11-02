import Foundation
import Testing

@Suite("hats ls", .tags(.e2e))
struct ProfileListingTests {
    private func row(_ name: String, in rows: [[String: Any]]) throws -> [String: Any] {
        try #require(rows.first { $0["name"] as? String == name })
    }

    @Test func aFreshInstallListsOnlyDefault() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(["ls"])

        #expect(result.exit == 0, "\(result)")
        let lines = result.stdout.split(separator: "\n").map(String.init)
        #expect(lines.count == 2, "\(result)")
        #expect(lines[0].hasPrefix("PROFILE"), "\(result)")
        #expect(lines[1].hasPrefix("default"), "\(result)")
        #expect(lines[1].hasSuffix("Claude.app"), "\(result)")
    }

    @Test func sizeAddsDiskUsage() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")

        let table = try sandbox.hats(["ls", "--size"])
        let json = try sandbox.hats(["ls", "--json", "--size"])

        #expect(table.stdout.contains("DISK"), "\(table)")
        #expect(!(try sandbox.hats(["ls"]).stdout.contains("DISK")))
        #expect(try row("work", in: sandbox.json(json))["diskBytes"] is Int, "\(json)")
    }

    @Test func accountFieldsComeFromTheSeededFiles() throws {
        let sandbox = try E2ESandbox()
        let dir = sandbox.profileDir("work")
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        try sandbox.write(
            #"{"oauth:tokenCache":"\#(sandbox.sentinel)","lastKnownAccountUuid":"acct-desktop"}"#, to: "\(dir)/desktop/config.json")
        try sandbox.write(
            #"{"accessToken":"\#(sandbox.sentinel)","oauthAccount":{"accountUuid":"acct-code","emailAddress":"me@example.com","organizationName":"Acme"}}"#,
            to: "\(dir)/code/.claude.json")

        let json = try sandbox.hats(["ls", "--json"])
        let table = try sandbox.hats(["ls"])

        let account = try #require(try row("work", in: sandbox.json(json))["account"] as? [String: Any])
        #expect(account["desktop"] as? String == "signed-in")
        #expect(account["desktopAccountID"] as? String == "acct-desktop")
        #expect(account["codeAccountID"] as? String == "acct-code")
        #expect(account["codeEmail"] as? String == "me@example.com")
        #expect(account["codeOrganization"] as? String == "Acme")
        #expect(table.stdout.contains("me@example.com (Acme) [Desktop on another account]"), "\(table)")
    }

    @Test func cliLoginComesFromTheSeededKeychain() throws {
        let sandbox = try E2ESandbox()
        let work = try sandbox.addProfile("work")
        try sandbox.addProfile("other")
        try sandbox.seedKeychain([sandbox.keychainService(forConfigDir: work), sandbox.keychainService(forConfigDir: nil)])

        let rows = try sandbox.json(try sandbox.hats(["ls", "--json"]))

        #expect(try row("work", in: rows)["cliLogin"] as? String == "present")
        #expect(try row("other", in: rows)["cliLogin"] as? String == "absent")
        #expect(try row("default", in: rows)["cliLogin"] as? String == "present")
    }

    @Test func anUnreadableKeychainListIsUnknownRatherThanAnError() throws {
        let sandbox = try E2ESandbox()
        try sandbox.write("{ not json", to: "\(sandbox.testDir)/keychain.json")

        let rows = try sandbox.json(try sandbox.hats(["ls", "--json"]))

        #expect(try row("default", in: rows)["cliLogin"] as? String == "unknown")
    }

    @Test func aRemovedLauncherReadsMissing() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        #expect(try sandbox.hats(["ls"]).stdout.split(separator: "\n").contains { $0.hasPrefix("work") && $0.hasSuffix("ok") })

        #expect(try sandbox.hats(["rm", "work"]).exit == 0)

        let result = try sandbox.hats(["ls"])
        #expect(result.stdout.split(separator: "\n").contains { $0.hasPrefix("work") && $0.hasSuffix("missing") }, "\(result)")
    }
}
