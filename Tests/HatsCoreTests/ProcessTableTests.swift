import Foundation
import Testing
@testable import HatsCore

@Suite struct ProcArgsParserTests {
    static func buffer(argc: Int32, exec: String, padding: Int, args: [String], env: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array(exec.utf8) + [0] + Array(repeating: 0, count: padding)
        for item in args + env { bytes += Array(item.utf8) + [0] }
        return bytes + [0, 0]
    }

    @Test func parsesArgsAndEnvironment() throws {
        let bytes = Self.buffer(
            argc: 2, exec: "/Applications/Claude.app/Contents/MacOS/Claude", padding: 3,
            args: ["/Applications/Claude.app/Contents/MacOS/Claude", "--user-data-dir=/x/Application Support/y"],
            env: ["CLAUDE_CONFIG_DIR=/x/code", "EMPTY=", "WEIRD=a=b"]
        )
        let details = try #require(ProcArgsParser.parse(bytes))
        #expect(details.executablePath == "/Applications/Claude.app/Contents/MacOS/Claude")
        #expect(details.arguments.count == 2)
        #expect(details.argumentValue("--user-data-dir") == "/x/Application Support/y")
        #expect(details.claudeConfigDir == "/x/code")
    }

    @Test func keepsNoEnvironmentVariableButTheConfigDir() throws {
        let bytes = Self.buffer(
            argc: 1, exec: "/x/claude", padding: 0, args: ["claude"],
            env: ["ANTHROPIC_API_KEY=sk-ant-secret", "CLAUDE_CONFIG_DIR=/x/code", "GITHUB_TOKEN=ghp_secret"]
        )
        let details = try #require(ProcArgsParser.parse(bytes))
        let stored = String(reflecting: details)
        #expect(details.claudeConfigDir == "/x/code")
        #expect(!stored.contains("secret"))
        #expect(!stored.contains("ANTHROPIC_API_KEY"))
    }

    @Test func rejectsTruncatedBuffers() {
        #expect(ProcArgsParser.parse([1, 0]) == nil)
        #expect(ProcArgsParser.parse(Self.buffer(argc: 3, exec: "/bin/x", padding: 0, args: ["x"], env: []).dropLast(2).map { $0 }) == nil)
    }

    @Test func argumentValueSupportsSeparateFormAndLastWins() {
        let details = ProcessDetails(
            executablePath: "/x", arguments: ["x", "--user-data-dir", "/a", "--user-data-dir=/b"], claudeConfigDir: nil)
        #expect(details.argumentValue("--user-data-dir") == "/b")
        #expect(details.argumentValue("--user-data") == nil)
    }
}

#if os(macOS)
@Suite(.tags(.integration)) struct DarwinProcessTableTests {
    @Test func readsOwnProcess() throws {
        let table = DarwinProcessTable()
        let pid = ProcessInfo.processInfo.processIdentifier
        let summary = try #require(table.summaries().first { $0.pid == pid })
        #expect(summary.parentPID == getppid())
        #expect(abs(summary.startTime.timeIntervalSinceNow) < 3_600)
        let details = try #require(table.details(of: pid))
        #expect(details.claudeConfigDir == ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"])
        #expect(!details.arguments.isEmpty)
    }
}
#endif

extension Tag {
    @Tag static var integration: Self
}
