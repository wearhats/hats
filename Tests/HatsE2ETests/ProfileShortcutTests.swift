import Foundation
import Testing

@Suite("Profile shortcuts", .tags(.e2e))
struct ProfileShortcutTests {
    @Test func runResolvesAShortcutToTheFullProfile() throws {
        let sandbox = try E2ESandbox()
        let codeDir = try sandbox.addProfile("work", shortcut: "w")

        let result = try sandbox.hats(
            ["run", "w", "--", "-c", #"echo "$CLAUDE_CONFIG_DIR $HATS_PROFILE""#], environment: ["HATS_CLAUDE_BIN": "/bin/bash"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "\(codeDir) work\n", "\(result)")
    }

    @Test func execAndEnvResolveAShortcut() throws {
        let sandbox = try E2ESandbox()
        let codeDir = try sandbox.addProfile("work", shortcut: "w")

        let exec = try sandbox.hats(["exec", "w", "--", "printenv", "HATS_PROFILE"])
        let env = try sandbox.hats(["env", "w"])

        #expect(exec.stdout == "work\n", "\(exec)")
        #expect(env.stdout.contains(codeDir), "\(env)")
    }

    @Test func lsJSONShowsTheShortcutOnlyWhereThereIsOne() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work", shortcut: "w")
        try sandbox.addProfile("other")

        let result = try sandbox.hats(["ls", "--json"])

        let rows = try #require(try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [[String: Any]], "\(result)")
        #expect(rows.first { $0["name"] as? String == "work" }?["shortcut"] as? String == "w", "\(result)")
        #expect(rows.first { $0["name"] as? String == "other" }?["shortcut"] == nil, "\(result)")
    }

    @Test func lsTableShowsTheShortcutBesideTheName() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work", shortcut: "w")

        let result = try sandbox.hats(["ls"])

        #expect(result.stdout.contains("work (w)"), "\(result)")
    }
}
