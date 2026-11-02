import Foundation
import Testing

/// `/bin/bash` stands in for claude: unlike a shebang stub, it shows the argv0 it
/// was really given as `$0`. Test mode refuses a `HATS_CLAUDE_BIN` outside the
/// sandbox, and macOS kills a copied system binary, so these run with test mode
/// off. `run` touches nothing but the profile's files before it execs.
@Suite("hats run", .tags(.e2e))
struct RunCommandTests {
    private let claude = ["HATS_CLAUDE_BIN": "/bin/bash"]
    private let testModeOff: Set<String> = ["HATS_TEST_SANDBOX"]

    @Test func execsClaudeWithTheProfileEnvironment() throws {
        let sandbox = try E2ESandbox()
        let codeDir = try sandbox.addProfile("t1")

        let result = try sandbox.hats(
            ["run", "t1", "--", "-c", #"echo "$$ $CLAUDE_CONFIG_DIR $HATS_PROFILE""#], environment: claude, removing: testModeOff)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "\(result.pid) \(codeDir) t1\n", "\(result)")
    }

    @Test func passesArgumentsAfterTheTerminator() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")

        let result = try sandbox.hats(
            ["run", "t1", "--", "-c", #"printf '%s\n' "$@""#, "name", "--resume", "two words", "--"], environment: claude,
            removing: testModeOff)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "--resume\ntwo words\n--\n", "\(result)")
    }

    @Test func setsArgvZeroToClaude() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")

        let result = try sandbox.hats(["run", "t1", "--", "-c", "echo $0"], environment: claude, removing: testModeOff)

        #expect(result.stdout == "claude\n", "\(result)")
    }

    @Test func propagatesTheExitStatus() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")

        let result = try sandbox.hats(["run", "t1", "--", "-c", "exit 7"], environment: claude, removing: testModeOff)

        #expect(result.exit == 7, "\(result)")
    }

    @Test func aMissingClaudeExplainsTheOverride() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")
        let emptyPath = "\(sandbox.root)/empty-path"
        try sandbox.makeDirectory(emptyPath)

        let result = try sandbox.hats(["run", "t1"], environment: ["PATH": emptyPath])

        #expect(result.exit == 1, "\(result)")
        #expect(
            result.stderr == "hats: claude CLI not found on PATH\nhint: install Claude Code, or set HATS_CLAUDE_BIN\n", "\(result)")
    }

    @Test func aNonExecutableOverrideFails() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")
        let notExecutable = "\(sandbox.root)/claude"
        try sandbox.write("#!/bin/sh\n", to: notExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: notExecutable)

        let result = try sandbox.hats(["run", "t1"], environment: ["HATS_CLAUDE_BIN": notExecutable])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("set HATS_CLAUDE_BIN"), "\(result)")
    }
}
