import Foundation
import Testing

@Suite("hats dock", .tags(.e2e))
struct DockCommandTests {
    @Test func pinWritesAPercentEncodedTileAndRestartsOnce() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)

        let result = try sandbox.hats(["dock", "pin", "work"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "Pinned Claude (Work) to the Dock.\n", "\(result)")
        let tiles = try sandbox.dockTiles()
        #expect(tiles.count == 1)
        #expect(tiles.first?.hasPrefix("file://") == true)
        #expect(tiles.first?.hasSuffix("Claude%20(Work).app/") == true, "\(tiles)")
        #expect(try sandbox.events("dock-write").count == 1)
        #expect(try sandbox.events("dock-restart").count == 1)
    }

    /// Rule 5: nothing is written, and the Dock isn't restarted, when nothing changes.
    @Test func aSecondPinWritesNothingAndRestartsNothing() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work", "--pin"]).exit == 0)
        let before = try sandbox.events().count

        let result = try sandbox.hats(["dock", "pin", "work"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "Claude (Work) is already in the Dock.\n", "\(result)")
        #expect(try sandbox.events().count == before)
    }

    @Test func dedupeClaudeKeepsTheFirstClaudeTile() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        let app = try sandbox.makeApp()
        let appURL = URL(filePath: app, directoryHint: .isDirectory).absoluteString
        try sandbox.seedDock(urls: ["file:///Applications/Safari.app/", appURL, appURL, "file:///Applications/Mail.app/", appURL])

        let result = try sandbox.hats(["dock", "pin", "work", "--dedupe-claude"], environment: ["HATS_CLAUDE_APP": app])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("Removed 2 duplicate Claude.app tile(s)"), "\(result)")
        let tiles = try sandbox.dockTiles()
        #expect(tiles.filter { $0 == appURL }.count == 1, "\(tiles)")
        #expect(tiles.first == "file:///Applications/Safari.app/", "\(tiles)")
        #expect(tiles.contains("file:///Applications/Mail.app/"), "\(tiles)")
        #expect(tiles[2].hasSuffix("Claude%20(Work).app/"), "the launcher goes right after Claude.app: \(tiles)")
    }

    @Test func dedupeClaudeWithoutAClaudeAppFails() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)

        let result = try sandbox.hats(["dock", "pin", "work", "--dedupe-claude"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("Claude Desktop is not installed"), "\(result)")
        #expect(try sandbox.events("dock-write").isEmpty)
    }

    @Test func unpinLeavesUnrelatedTiles() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        try sandbox.seedDock(urls: ["file:///Applications/Safari.app/"])
        #expect(try sandbox.hats(["dock", "pin", "work"]).exit == 0)
        #expect(try sandbox.dockTiles().count == 2)

        let result = try sandbox.hats(["dock", "unpin", "work"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "Removed Claude (Work) from the Dock.\n", "\(result)")
        #expect(try sandbox.dockTiles() == ["file:///Applications/Safari.app/"])
    }

    @Test func unpinWithNothingPinnedWritesNothing() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        let before = try sandbox.events().count

        let result = try sandbox.hats(["dock", "unpin"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "No launchers were in the Dock.\n", "\(result)")
        #expect(try sandbox.events().count == before)
    }
}
