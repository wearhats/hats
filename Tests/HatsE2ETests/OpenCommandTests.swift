import Foundation
import Testing

@Suite("hats open", .tags(.e2e))
struct OpenCommandTests {
    @Test func aProfileLaunchesAnIsolatedNewInstance() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        let app = try sandbox.makeApp()

        let result = try sandbox.hats(["open", "work"], environment: ["HATS_CLAUDE_APP": app])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.hasPrefix("Launched Claude (Work), pid"), "\(result)")
        let launch = try #require(try sandbox.events("launch").first)
        #expect(launch["app"] as? String == app)
        #expect(launch["newInstance"] as? Bool == true)
        #expect(launch["arguments"] as? [String] == ["--user-data-dir=\(sandbox.profileDir("work"))/desktop"])
        #expect(launch["environment"] as? [String: String] == ["CLAUDE_CONFIG_DIR": code])
    }

    @Test func defaultOpensTheStockAppWithNoArguments() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(["open", "default"], environment: try sandbox.withClaudeApp)

        #expect(result.exit == 0, "\(result)")
        let launch = try #require(try sandbox.events("launch").first)
        #expect(launch["newInstance"] as? Bool == false)
        #expect(launch["arguments"] as? [String] == [])
        #expect(launch["environment"] as? [String: String] == [:])
    }

    @Test func allOpensEveryProfileExceptDefault() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        try sandbox.addProfile("other")

        let result = try sandbox.hats(["open", "--all"], environment: try sandbox.withClaudeApp)

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.events("launch").count == 2)
    }

    @Test func aMissingAppOverrideFails() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")

        let result = try sandbox.hats(["open", "work"], environment: ["HATS_CLAUDE_APP": "\(sandbox.root)/Missing.app"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("HATS_CLAUDE_APP points to a missing app"), "\(result)")
        #expect(try sandbox.events("launch").isEmpty)
    }

    @Test func withoutAnOverrideClaudeIsNotInstalled() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")

        let result = try sandbox.hats(["open", "work"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("Claude Desktop is not installed"), "\(result)")
        #expect(try sandbox.events("launch").isEmpty)
    }
}
