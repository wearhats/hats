import Foundation
import Testing

@Suite("hats ls", .tags(.e2e))
struct ListCommandTests {
    @Test func pathsAddsTheDesktopAndConfigDirsAsTheLastColumns() throws {
        let sandbox = try E2ESandbox()
        let managed = try sandbox.addProfile("work")
        let adopted = try sandbox.addProfile("client", adopting: "\(sandbox.root)/adopted/client dir")

        let result = try sandbox.hats(["ls", "--paths"])

        #expect(result.exit == 0, "\(result)")
        let lines = result.stdout.split(separator: "\n").map(String.init)
        #expect(columns(ofHeader: lines.first).suffix(2) == ["DESKTOP DIR", "CONFIG DIR"], "\(result)")

        let work = try #require(row("work", in: lines), "\(result)")
        #expect(work.contains("\(sandbox.hatsHome)/profiles/work/desktop"), "\(result)")
        #expect(work.hasSuffix(managed), "\(result)")

        let client = try #require(row("client", in: lines), "\(result)")
        #expect(client.contains("\(sandbox.hatsHome)/profiles/client/desktop"), "\(result)")
        #expect(client.hasSuffix(adopted), "\(result)")

        let stock = try #require(row("default", in: lines), "\(result)")
        #expect(stock.contains("/Library/Application Support/Claude"), "\(result)")
        #expect(stock.hasSuffix("/.claude"), "\(result)")
    }

    @Test func pathsStayAfterTheDiskColumn() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("work")

        let result = try sandbox.hats(["ls", "--paths", "--size"])

        #expect(result.exit == 0, "\(result)")
        let header = result.stdout.split(separator: "\n").first.map(String.init)
        #expect(columns(ofHeader: header).suffix(4) == ["DISK", "LAUNCHER", "DESKTOP DIR", "CONFIG DIR"], "\(result)")
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

    private func columns(ofHeader header: String?) -> [String] {
        (header ?? "").split(separator: "  ", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func row(_ name: String, in lines: [String]) -> String? {
        lines.first { $0.hasPrefix("\(name) ") }
    }
}
