import ArgumentParser
import Darwin
import Foundation
import HatsCore

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the claude CLI with the profile's account and settings.",
        discussion: "Example: hats run personal -- --resume",
        aliases: ["r"]
    )

    @OptionGroup var profile: ProfileArgument

    @Argument(parsing: .postTerminator, help: "Arguments passed to claude.")
    var claudeArguments: [String] = []

    func run() throws {
        let context = try Context()
        let target = try context.profile(profile.name)
        guard
            let claude = ExecutableLocator.find(
                "claude", override: context.environment["HATS_CLAUDE_BIN"], environment: context.environment)
        else {
            throw HatsError(.environment, "claude CLI not found on PATH", hint: "install Claude Code, or set HATS_CLAUDE_BIN")
        }
        try context.testSandbox?.requireInside(claude.plainPath, what: "the claude CLI")
        try ProcessExec.replace(
            with: claude, arguments: ["claude"] + claudeArguments, environment: ProfileEnvironment.apply(target, to: context.environment))
    }
}

struct Exec: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run any command with the profile's environment.",
        discussion: "Example: hats exec personal -- printenv CLAUDE_CONFIG_DIR",
        aliases: ["x"]
    )

    @OptionGroup var profile: ProfileArgument

    @Argument(parsing: .postTerminator, help: "The command and its arguments.")
    var command: [String] = []

    func validate() throws {
        guard !command.isEmpty else { throw ValidationError("missing command; usage: hats exec <name> -- <command> [args...]") }
    }

    func run() throws {
        let context = try Context()
        let target = try context.profile(profile.name)
        let environment = ProfileEnvironment.apply(target, to: context.environment)
        guard let executable = ExecutableLocator.find(command[0], environment: environment) else {
            throw HatsError(.notFound, "command not found: \(command[0])")
        }
        try ProcessExec.replace(with: executable, arguments: command, environment: environment)
    }
}

struct Env: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print shell code that selects the profile, for eval or a direnv .envrc.",
        discussion: #"Example: eval "$(hats env personal)""#
    )

    enum Shell: String, ExpressibleByArgument, CaseIterable {
        case zsh, bash, sh, fish
    }

    @OptionGroup var profile: ProfileArgument

    @Option(help: "Shell syntax to print.")
    var shell: Shell = .zsh

    func run() throws {
        let target = try Context().profile(profile.name)
        if target.isDefault {
            print(shell == .fish ? "set -e CLAUDE_CONFIG_DIR" : "unset CLAUDE_CONFIG_DIR")
            return
        }
        let value = Output.shellQuote(target.codeDir.plainPath)
        print(shell == .fish ? "set -gx CLAUDE_CONFIG_DIR \(value)" : "export CLAUDE_CONFIG_DIR=\(value)")
    }
}

enum ProfileEnvironment {
    static func apply(_ profile: Profile, to environment: [String: String]) -> [String: String] {
        var result = environment
        if profile.isDefault {
            result.removeValue(forKey: "CLAUDE_CONFIG_DIR")
        } else {
            result["CLAUDE_CONFIG_DIR"] = profile.codeDir.plainPath
        }
        result["HATS_PROFILE"] = profile.name.rawValue
        return result
    }
}

enum ProcessExec {
    /// Replaces the current process so signals, the TTY and the exit code
    /// belong to the child, as if it had been started directly.
    static func replace(with executable: URL, arguments: [String], environment: [String: String]) throws -> Never {
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        execve(executable.plainPath, argv, envp)
        throw HatsError(.io, "cannot execute \(executable.plainPath): \(String(cString: strerror(errno)))")
    }
}
