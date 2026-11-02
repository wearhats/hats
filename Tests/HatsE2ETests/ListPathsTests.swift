import Foundation
import Testing

@Suite("hats ls --paths", .tags(.e2e))
struct ListPathsTests {
    @Test func addsFullPathsAsTheLastColumns() throws {
        let sandbox = try E2ESandbox()
        let managed = try sandbox.addProfile("work")
        let adopted = try sandbox.addProfile("client", adopting: "\(sandbox.root)/adopted/client dir")

        let result = try sandbox.hats(["ls", "--paths"])

        #expect(result.exit == 0, "\(result)")
        let lines = result.stdout.split(separator: "\n").map(String.init)
        let header = try #require(lines.first, "\(result)")
        #expect(cells(header).suffix(2) == ["DESKTOP DIR", "CONFIG DIR"], "\(result)")
        #expect(cells(of: "work", in: lines).suffix(2) == ["\(sandbox.hatsHome)/profiles/work/desktop", managed], "\(result)")
        #expect(cells(of: "client", in: lines).suffix(2) == ["\(sandbox.hatsHome)/profiles/client/desktop", adopted], "\(result)")
        #expect(
            cells(of: "default", in: lines).suffix(2) == ["\(sandbox.home)/Library/Application Support/Claude", sandbox.defaultConfigDir],
            "\(result)")
    }

    @Test func stayAfterTheDiskColumnWithEachCellUnderItsHeader() throws {
        let sandbox = try E2ESandbox()
        let managed = try sandbox.addProfile("work")

        let result = try sandbox.hats(["ls", "--paths", "--size"])

        #expect(result.exit == 0, "\(result)")
        let lines = result.stdout.split(separator: "\n").map(String.init)
        let header = cells(try #require(lines.first, "\(result)"))
        let work = cells(of: "work", in: lines)
        #expect(header.suffix(4) == ["DISK", "LAUNCHER", "DESKTOP DIR", "CONFIG DIR"], "\(result)")
        #expect(work.count == header.count, "\(result)")
        #expect(work.suffix(3) == ["missing", "\(sandbox.hatsHome)/profiles/work/desktop", managed], "\(result)")
    }

    @Test func anEmojiInAPathDoesNotCutOffTheCell() throws {
        let sandbox = try E2ESandbox(hatsHomeName: "hats-home-🎩")
        let managed = try sandbox.addProfile("widest-profile-name")

        let result = try sandbox.hats(["ls", "--paths"])

        #expect(result.exit == 0, "\(result)")
        let lines = result.stdout.split(separator: "\n").map(String.init)
        #expect(
            cells(of: "widest-profile-name", in: lines).suffix(2) == ["\(sandbox.hatsHome)/profiles/widest-profile-name/desktop", managed],
            "\(result)")
    }

    @Test func theDefaultTableLeavesPathsOut() throws {
        let sandbox = try E2ESandbox()
        let managed = try sandbox.addProfile("work")

        let result = try sandbox.hats(["ls"])

        #expect(result.exit == 0, "\(result)")
        #expect(!result.stdout.contains("DESKTOP DIR"), "\(result)")
        #expect(!result.stdout.contains("CONFIG DIR"), "\(result)")
        #expect(!result.stdout.contains(managed), "\(result)")
    }

    private func cells(_ line: String) -> [String] {
        line.split(separator: "  ").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func cells(of profile: String, in lines: [String]) -> [String] {
        cells(lines.first { $0.hasPrefix("\(profile) ") } ?? "")
    }
}
