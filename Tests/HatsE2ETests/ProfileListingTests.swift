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

/// Every key always appears, with `null` for no value. Exact key sets also catch a
/// field forgotten in a hand-written encoder. Adding a key is fine and means
/// updating these; renaming or removing one breaks scripts.
@Suite("JSON contract", .tags(.e2e))
struct JSONContractTests {
    private let listKeys: Set<String> = [
        "name", "shortcut", "label", "color", "icon", "desktopDir", "codeDir", "launcher", "cliLogin", "account", "runningDesktop",
        "runningSessions", "diskBytes",
    ]
    private let accountKeys: Set<String> = ["desktop", "desktopAccountID", "codeAccountID", "codeEmail", "codeOrganization"]
    private let findingKeys: Set<String> = ["level", "check", "message", "hint"]

    @Test func lsAlwaysPrintsEveryKey() throws {
        let sandbox = try E2ESandbox()
        let rows = try sandbox.json(try sandbox.hats(["ls", "--json"]))

        let row = try #require(rows.first)
        #expect(Set(row.keys) == listKeys)
        #expect(row["launcher"] is NSNull)
        #expect(row["diskBytes"] is NSNull)
        #expect(row["shortcut"] is NSNull)
        let account = try #require(row["account"] as? [String: Any])
        #expect(Set(account.keys) == accountKeys)
        #expect(account["codeEmail"] is NSNull)
    }

    @Test func lsValuesHaveTheDocumentedTypes() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work", "--shortcut", "w"]).exit == 0)

        let rows = try sandbox.json(try sandbox.hats(["ls", "--json", "--size"]))

        let row = try #require(rows.first { $0["name"] as? String == "work" })
        #expect(Set(row.keys) == listKeys)
        for key in ["name", "shortcut", "label", "color", "icon", "desktopDir", "codeDir", "launcher", "cliLogin"] {
            #expect(row[key] is String, "\(key)")
        }
        for key in ["runningDesktop", "runningSessions", "diskBytes"] { #expect(row[key] is Int, "\(key)") }
    }

    @Test func doctorAlwaysPrintsEveryKey() throws {
        let sandbox = try E2ESandbox()

        let findings = try sandbox.json(try sandbox.hats(["doctor", "--json"]))

        #expect(!findings.isEmpty)
        for finding in findings { #expect(Set(finding.keys) == findingKeys, "\(finding)") }
        #expect(findings.contains { $0["hint"] is NSNull })
        #expect(findings.contains { $0["hint"] is String })
    }
}
