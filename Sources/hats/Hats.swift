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
            let updates = UpdateNotifier.start(for: command)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            await updates?.finish()
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
    let touchpoints: Touchpoints
    let testSandbox: TestSandbox?
    let unreadableWarnings = UnreadableProfileWarnings()

    init() throws {
        layout = Layout(environment: environment)
        store = ProfileStore(layout: layout)
        testSandbox = try TestSandbox(environment: environment, layout: layout)
        touchpoints = testSandbox?.touchpoints ?? .system(hatsVersion: Hats.version)
    }

    var processes: any ProcessTable { touchpoints.processes }
    var control: any AppControl { touchpoints.control }
    var credentials: any CredentialProbe { touchpoints.credentials }
    var launchers: LauncherBuilder { LauncherBuilder(layout: layout, registrar: touchpoints.registrar) }
    var dock: DockEditor { DockEditor(preferences: touchpoints.dock) }

    /// A folder named on the command line, which test mode must keep contained.
    func directoryArgument(_ path: String, flag: String) throws -> URL {
        // An unset shell variable must not silently mean the current directory.
        guard let directory = layout.directory(named: path) else { throw HatsError(.usage, "\(flag) needs a directory") }
        try testSandbox?.requireInside(directory.plainPath, what: flag)
        return directory
    }

    func profile(_ raw: String) throws -> Profile {
        try store.profile(matching: raw)
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
