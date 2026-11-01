import Testing

@Suite("hats exec", .tags(.e2e))
struct ExecCommandTests {
    /// Signals, the terminal and the exit status belong to the child only if
    /// hats replaced itself rather than wrapping it.
    @Test func replacesItselfWithTheCommand() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")

        let result = try sandbox.hats(["exec", "t1", "--", "/bin/sh", "-c", "echo $$"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "\(result.pid)\n", "\(result)")
    }

    @Test func setsTheConfigDirAndProfileName() throws {
        let sandbox = try E2ESandbox()
        let codeDir = try sandbox.addProfile("t1")

        let result = try sandbox.hats(["exec", "t1", "--", "/bin/sh", "-c", #"echo "$CLAUDE_CONFIG_DIR $HATS_PROFILE""#])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "\(codeDir) t1\n", "\(result)")
    }

    @Test func propagatesTheExitStatus() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")

        let result = try sandbox.hats(["exec", "t1", "--", "/bin/sh", "-c", "exit 7"])

        #expect(result.exit == 7, "\(result)")
    }

    @Test func overridesAnInheritedConfigDir() throws {
        let sandbox = try E2ESandbox()
        let codeDir = try sandbox.addProfile("t1")

        let result = try sandbox.hats(
            ["exec", "t1", "--", "printenv", "CLAUDE_CONFIG_DIR"], environment: ["CLAUDE_CONFIG_DIR": "\(sandbox.root)/inherited"])

        #expect(result.stdout == "\(codeDir)\n", "\(result)")
    }

    @Test func defaultDropsAnInheritedConfigDir() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(
            ["exec", "default", "--", "/bin/sh", "-c", #"echo "${CLAUDE_CONFIG_DIR-unset} $HATS_PROFILE""#],
            environment: ["CLAUDE_CONFIG_DIR": "\(sandbox.root)/inherited"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "unset default\n", "\(result)")
    }

    @Test func keepsOtherEnvironmentVariables() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")

        let result = try sandbox.hats(["exec", "t1", "--", "printenv", "E2E_MARKER"], environment: ["E2E_MARKER": "kept"])

        #expect(result.stdout == "kept\n", "\(result)")
    }

    @Test func anUnknownCommandFails() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")

        let result = try sandbox.hats(["exec", "t1", "--", "no-such-command"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr == "hats: command not found: no-such-command\n", "\(result)")
    }

    @Test func aMissingCommandIsAUsageError() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")

        let result = try sandbox.hats(["exec", "t1"])

        #expect(result.exit == 64, "\(result)")
        #expect(result.stderr.contains("missing command"), "\(result)")
    }
}
