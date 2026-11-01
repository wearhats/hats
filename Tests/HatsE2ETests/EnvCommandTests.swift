import Testing

@Suite("hats env", .tags(.e2e))
struct EnvCommandTests {
    @Test(arguments: ["zsh", "bash", "sh"])
    func printsAnExportLineForPosixShells(shell: String) throws {
        let sandbox = try E2ESandbox()
        let codeDir = try sandbox.addProfile("t1")

        let result = try sandbox.hats(["env", "t1", "--shell", shell])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "export CLAUDE_CONFIG_DIR='\(codeDir)'\n", "\(result)")
    }

    @Test func zshIsTheDefaultSyntax() throws {
        let sandbox = try E2ESandbox()
        let codeDir = try sandbox.addProfile("t1")

        let result = try sandbox.hats(["env", "t1"])

        #expect(result.stdout == "export CLAUDE_CONFIG_DIR='\(codeDir)'\n", "\(result)")
    }

    @Test func printsSetForFish() throws {
        let sandbox = try E2ESandbox()
        let codeDir = try sandbox.addProfile("t1")

        let result = try sandbox.hats(["env", "t1", "--shell", "fish"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "set -gx CLAUDE_CONFIG_DIR '\(codeDir)'\n", "\(result)")
    }

    @Test(arguments: [("zsh", "unset CLAUDE_CONFIG_DIR\n"), ("fish", "set -e CLAUDE_CONFIG_DIR\n")])
    func defaultUnsetsTheConfigDir(shell: String, expected: String) throws {
        let result = try E2ESandbox().hats(["env", "default", "--shell", shell])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == expected, "\(result)")
    }

    @Test func aPathWithAQuoteAndSpaceSurvivesEval() throws {
        let sandbox = try E2ESandbox(hatsHomeName: "it's a home")
        let codeDir = try sandbox.addProfile("t1")
        let printed = try sandbox.hats(["env", "t1", "--shell", "sh"])
        try #require(printed.exit == 0, "\(printed)")

        let evaluated = try sandbox.guarded("/bin/sh", ["-c", #"eval "$1"; printf %s "$CLAUDE_CONFIG_DIR""#, "sh", printed.stdout])

        #expect(evaluated.exit == 0, "\(evaluated)")
        #expect(evaluated.stdout == codeDir, "\(evaluated)")
    }

    @Test func anAdoptedProfileExportsItsAdoptedDir() throws {
        let sandbox = try E2ESandbox()
        let adopted = "\(sandbox.root)/claude-work"
        try sandbox.addProfile("t1", adopting: adopted)

        let result = try sandbox.hats(["env", "t1"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "export CLAUDE_CONFIG_DIR='\(adopted)'\n", "\(result)")
    }
}
