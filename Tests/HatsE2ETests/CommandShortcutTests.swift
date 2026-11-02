import Foundation
import Testing

@Suite("Command shortcuts", .tags(.e2e))
struct CommandShortcutTests {
    @Test func runShortcutExecsClaudeWithTheProfileEnvironment() throws {
        let sandbox = try E2ESandbox()
        let codeDir = try sandbox.addProfile("t1")

        let result = try sandbox.hats(
            ["r", "t1", "--", "-c", #"echo "$0 $CLAUDE_CONFIG_DIR $HATS_PROFILE""#], environment: ["HATS_CLAUDE_BIN": "/bin/bash"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "claude \(codeDir) t1\n", "\(result)")
    }

    @Test func execShortcutRunsTheCommandWithTheProfileEnvironment() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")

        let result = try sandbox.hats(["x", "t1", "--", "printenv", "HATS_PROFILE"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "t1\n", "\(result)")
    }

    /// An unknown target stops both commands before they launch or focus
    /// anything, and only the real command can print this message.
    @Test(arguments: [
        (["o", "ghost"], "no profile named 'ghost'"),
        (["f", "ghost"], "no running instance matches 'ghost'"),
    ])
    func shortcutReachesTheFullCommand(arguments: [String], stderr: String) throws {
        let result = try E2ESandbox().hats(arguments)

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains(stderr), "\(result)")
    }

    @Test(arguments: ["run, r", "open, o", "exec, x", "focus, f"])
    func helpListsTheShortcut(label: String) throws {
        let result = try E2ESandbox().hats(["--help"])

        #expect(result.stdout.contains(label), "\(result)")
    }
}
