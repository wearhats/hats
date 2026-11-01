import Foundation
import Testing

@Suite("Unreadable profiles", .tags(.e2e))
struct UnreadableProfileTests {
    @Test func lsJSONKeepsStdoutValidAndWarnsAboutTheBrokenProfile() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        try sandbox.addProfile("broken")
        try sandbox.write("{ not json", to: "\(sandbox.hatsHome)/profiles/broken/profile.json")

        let result = try sandbox.hats(["ls", "--json"])

        #expect(result.exit == 0, "\(result)")
        let json = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
        let rows = try #require(json as? [[String: Any]], "\(result)")
        #expect(rows.contains { $0["name"] as? String == "work" }, "\(result)")
        #expect(!rows.contains { $0["name"] as? String == "broken" }, "\(result)")

        let lines = result.stderr.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let warning = try #require(warningIndex(in: lines, naming: "broken"), "\(result)")
        let hint = lines.indices.contains(warning + 1) ? lines[warning + 1] : ""
        #expect(hint.hasPrefix("hint:") && hint.contains("hats doctor"), "\(result)")
    }

    @Test(arguments: [["ls"], ["ls", "--json"], ["ps", "--json"], ["rm", "--all", "--dry-run"]])
    func aListingCommandWarnsOncePerUnreadableProfileAndNeverAboutHealthyOnes(arguments: [String]) throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")
        try sandbox.addProfile("other")
        try sandbox.addProfile("broken")
        try sandbox.write("{ not json", to: "\(sandbox.hatsHome)/profiles/broken/profile.json")

        let result = try sandbox.hats(arguments)

        #expect(result.exit == 0, "\(result)")
        #expect(warningCount(in: result.stderr, naming: "broken") == 1, "\(result)")
        #expect(warningCount(in: result.stderr, naming: "work") == 0, "\(result)")
        #expect(warningCount(in: result.stderr, naming: "other") == 0, "\(result)")
    }

    private func warningIndex(in lines: [String], naming name: String) -> Int? {
        lines.firstIndex { $0.hasPrefix("hats: warning:") && $0.contains("'\(name)'") }
    }

    private func warningCount(in stderr: String, naming name: String) -> Int {
        stderr.split(separator: "\n").count { $0.hasPrefix("hats: warning:") && $0.contains("'\(name)'") }
    }
}
