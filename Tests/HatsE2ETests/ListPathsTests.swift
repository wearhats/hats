import Foundation
import Testing

/// Only `--paths` without `--json` belongs here: it returns before hats scans
/// processes or queries the Keychain, which every other form of `ls` does.
@Suite("hats ls --paths", .tags(.e2e))
struct ListPathsTests {
    @Test func showsFullPathsInPlaceOfTheStatusColumns() throws {
        let sandbox = try E2ESandbox()
        let managed = try sandbox.addProfile("work")
        let adopted = try sandbox.addProfile("client", adopting: "\(sandbox.root)/adopted/client dir")

        let result = try sandbox.hats(["ls", "--paths"])

        #expect(result.exit == 0, "\(result)")
        let table = parseTable(result)
        #expect(table.first == ["PROFILE", "DESKTOP DIR", "CONFIG DIR"], "\(result)")
        #expect(try row("work", in: table) == ["work", "\(sandbox.hatsHome)/profiles/work/desktop", managed], "\(result)")
        #expect(try row("client", in: table) == ["client", "\(sandbox.hatsHome)/profiles/client/desktop", adopted], "\(result)")
        #expect(
            try row("default", in: table) == ["default", "\(sandbox.home)/Library/Application Support/Claude", sandbox.defaultConfigDir],
            "\(result)")
    }

    @Test func sizeAddsADiskColumnWithEveryCellUnderItsHeader() throws {
        let sandbox = try E2ESandbox()
        let managed = try sandbox.addProfile("work")

        let result = try sandbox.hats(["ls", "--paths", "--size"])

        #expect(result.exit == 0, "\(result)")
        let table = parseTable(result)
        #expect(table.first == ["PROFILE", "DISK", "DESKTOP DIR", "CONFIG DIR"], "\(result)")
        let work = try row("work", in: table)
        #expect(work.count == 4, "\(result)")
        #expect(work.dropFirst().first?.hasSuffix("B") == true, "\(result)")
        #expect(work.suffix(2) == ["\(sandbox.hatsHome)/profiles/work/desktop", managed], "\(result)")
        let columnLayouts = Set(result.stdout.split(separator: "\n").map(columnStarts))
        #expect(columnLayouts.count == 1, "\(result)")
    }

    @Test func anEmojiInAPathDoesNotCutOffTheCell() throws {
        let sandbox = try E2ESandbox(hatsHomeName: "hats-home-🎩")
        let managed = try sandbox.addProfile("widest-profile-name")

        let result = try sandbox.hats(["ls", "--paths"])

        #expect(result.exit == 0, "\(result)")
        let desktopDir = "\(sandbox.hatsHome)/profiles/widest-profile-name/desktop"
        #expect(try row("widest-profile-name", in: parseTable(result)) == ["widest-profile-name", desktopDir, managed], "\(result)")
    }

    @Test func aControlCharacterInAPathCannotSplitTheRow() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("client", adopting: "\(sandbox.root)/adopted/new\nline\u{1B}[31m")

        let result = try sandbox.hats(["ls", "--paths"])

        #expect(result.exit == 0, "\(result)")
        let client = try row("client", in: parseTable(result))
        #expect(client.last == "\(sandbox.root)/adopted/new?line?[31m", "\(result)")
    }

    @Test func showsTheShortcutBesideTheName() throws {
        let sandbox = try E2ESandbox()
        let managed = try sandbox.addProfile("work", shortcut: "w")

        let result = try sandbox.hats(["ls", "--paths"])

        #expect(result.exit == 0, "\(result)")
        #expect(
            try row("work (w)", in: parseTable(result)) == ["work (w)", "\(sandbox.hatsHome)/profiles/work/desktop", managed],
            "\(result)")
    }

    private func parseTable(_ result: CommandResult) -> [[String]] {
        result.stdout.split(separator: "\n").map { line in
            line.split(separator: "  ").map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    private func row(_ profile: String, in table: [[String]]) throws -> [String] {
        let match = table.first { $0.first == profile }
        return try #require(match, "no row for \(profile) in \(table)")
    }

    /// `parseTable` can't see this: a cell padded to the wrong width still splits into the same cells.
    private func columnStarts(_ line: Substring) -> [Int] {
        let characters = Array(line)
        let separator = Array(repeating: Character(" "), count: 2)
        return characters.indices.filter { index in
            index == 0 || (characters[index] != " " && characters[..<index].suffix(2).elementsEqual(separator))
        }
    }
}
