import ArgumentParser
import Foundation
import HatsCore

@main
struct Hats: AsyncParsableCommand {
    static let version = HatsVersion.current

    static let configuration = CommandConfiguration(
        commandName: "hats",
        abstract: "Run several Claude accounts side by side, and see every running Claude in one place.",
        discussion: """
            A profile isolates Claude Desktop (chats, login, MCP, Cowork) and the claude CLI, and hands its config dir to Desktop's Code tab.
            The stock install is the read-only 'default' profile and is never modified.
            """,
        version: version,
        subcommands: [
            Setup.self, Add.self, List.self, Open.self, Run.self, Exec.self, Env.self,
            PS.self, Focus.self, Reset.self, Dedupe.self, Remove.self, Doctor.self, Launcher.self, Dock.self,
        ]
    )

    /// Same as the default entry point, but renders `HatsError` with its hint
    /// and maps usage errors to EX_USAGE (64).
    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch let error as HatsError {
            Output.printError(error)
            Darwin.exit(error.kind == .usage ? EX_USAGE : EXIT_FAILURE)
        } catch {
            exit(withError: error)
        }
    }
}

/// Shared wiring so every command builds its dependencies the same way.
struct Context {
    let environment = ProcessInfo.processInfo.environment
    let layout: Layout
    let store: ProfileStore
    let processes: any ProcessTable = DarwinProcessTable()
    let control: any AppControl = WorkspaceAppControl()
    let folderOpener: any FolderOpener = WorkspaceFolderOpener()
    let credentials: any CredentialProbe = KeychainCredentialProbe()
    let unreadableWarnings = UnreadableProfileWarnings()

    init() {
        layout = Layout(environment: environment)
        store = ProfileStore(layout: layout)
    }

    func profile(_ raw: String) throws -> Profile {
        try store.profile(named: try ProfileName(raw))
    }

    /// Every profile that can be read. Each one that cannot is named on stderr
    /// once per run, however many times the run lists profiles.
    func readableProfiles() throws -> [Profile] {
        let inventory = try store.inventory()
        for broken in inventory.unreadableProfiles where unreadableWarnings.claimReport(for: broken.name) {
            Output.printWarning(
                "profile '\(broken.name)' cannot be read, so it is left out: \(broken.error.message)",
                hint: "run hats doctor to see what is wrong with it"
            )
        }
        return inventory.profiles
    }

    /// The path launchers should call: a stable `hats` on PATH (Homebrew's
    /// symlink survives upgrades) or, failing that, this binary itself.
    func hatsExecutablePath() -> String {
        if let onPath = ExecutableLocator.find("hats", environment: environment) {
            return onPath.plainPath
        }
        return runningExecutable().plainPath
    }

    func runningExecutable() -> URL {
        (Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])).standardizedFileURL.resolvingSymlinksInPath()
    }
}

/// A class, because a struct copy of `Context` could not record what it has
/// already reported, and every copy in one run must see the same record.
final class UnreadableProfileWarnings {
    private var reported: Set<ProfileName> = []

    func claimReport(for name: ProfileName) -> Bool {
        reported.insert(name).inserted
    }
}

struct ProfileArgument: ParsableArguments {
    @Argument(help: "Profile name (use 'default' for the stock install).")
    var name: String
}
