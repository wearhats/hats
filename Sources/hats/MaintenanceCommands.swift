import ArgumentParser
import Foundation
import HatsCore

struct Reset: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start a profile fresh: move its Desktop sign-in and data to the Trash, so it asks for a login again.",
        discussion: "Use it when a profile opens on the wrong account. Your Claude account itself is not touched."
    )

    @OptionGroup var profile: ProfileArgument

    @Flag(help: "Also reset the profile's own Claude Code dir (not allowed for an adopted one).")
    var code = false

    @Flag(help: "Open the profile afterwards, to sign in.")
    var open = false

    @Flag(help: "Do not ask for confirmation.")
    var yes = false

    @Flag(help: "Show what would be moved to the Trash, change nothing.")
    var dryRun = false

    func run() async throws {
        let context = Context()
        let target = try context.store.profile(fullName: profile.name)
        guard !target.isDefault else {
            throw HatsError(.usage, "the default profile is the stock Claude install; sign out inside Claude instead")
        }
        try context.refuseIfRunning(target, action: "reset it")
        let dirs = code ? [target.desktopDir, target.codeDir] : [target.desktopDir]
        if dryRun { return dirs.forEach { print("Would move \($0.plainPath) to the Trash.") } }

        print("This moves the local data of '\(target.name)' to the Trash:")
        dirs.forEach { print("  \($0.plainPath)") }
        guard try Prompt.confirm("Start '\(target.name)' fresh?", default: false, assumeYes: yes) else {
            return print("Nothing changed.")
        }
        for dir in try context.store.reset(target.name, includingCode: code) {
            print("Moved \(dir.plainPath) to the Trash.")
        }
        try LauncherBuilder(layout: context.layout).build(for: target, hatsPath: context.hatsExecutablePath())
        if open {
            try await context.open(target)
            print("\n" + Context.signInGuidance)
        } else {
            print("Next: hats open \(target.name), then sign in with the right account.")
        }
    }
}

struct Dedupe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Quit extra Claude Desktop windows that run on the same profile, keeping the oldest one.",
        discussion: """
            Two Claude processes on one data dir can corrupt it. Extras can appear when a launcher \
            without focus-if-running is clicked twice, or when a Claude update relaunches a \
            profile's window on the default profile. Quitting is graceful, like Cmd-Q.
            """
    )

    @Flag(help: "Do not ask for confirmation.")
    var yes = false

    @Flag(help: "Show what would be quit, change nothing.")
    var dryRun = false

    func run() async throws {
        let context = Context()
        let profiles = try context.readableProfiles()
        let groups = DuplicateInstances.groups(in: InstanceScanner(profiles: profiles, processes: context.processes).scan().instances)
        guard !groups.isEmpty else { return print("No duplicate Claude Desktop instances.") }
        for group in groups {
            let owner = group.keep.profile.map { "'\($0)'" } ?? group.dataDir
            print("\(owner): keep pid \(group.keep.pid), quit \(group.extras.map { String($0.pid) }.joined(separator: ", "))")
        }
        if dryRun { return }
        guard try Prompt.confirm("Quit the extra instances?", default: true, assumeYes: yes) else { return print("Nothing changed.") }
        var failed: [Int32] = []
        for pid in groups.flatMap(\.extras).map(\.pid) where !(await context.control.terminate(pid: pid)) {
            failed.append(pid)
        }
        if failed.isEmpty {
            print("Asked \(groups.flatMap(\.extras).count) instance(s) to quit.")
            if groups.contains(where: { $0.keep.profile?.isDefault == true }) {
                print("If a profile window came back as default after a Claude update, reopen your profiles with: hats open --all")
            }
        } else {
            throw HatsError(
                .environment, "could not quit pids \(failed.map(String.init).joined(separator: ", "))", hint: "quit them from the Dock")
        }
    }
}

struct Dock: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pin or unpin launchers in the Dock. Opt-in; restarts the Dock.",
        subcommands: [Pin.self, Unpin.self]
    )

    struct Pin: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Pin launchers to the Dock (all profiles by default).")

        @Argument(help: "Profiles to pin.")
        var names: [String] = []

        @Flag(help: "Also remove repeated Claude.app tiles, keeping the first one.")
        var dedupeClaude = false

        func run() throws {
            let context = Context()
            let targets =
                names.isEmpty
                ? try context.readableProfiles().filter { !$0.isDefault }
                : try names.map { try context.profile($0) }
            guard !targets.contains(where: \.isDefault) else { throw HatsError(.usage, "Claude.app itself is pinned the usual way") }
            if targets.isEmpty { return print("No profiles yet. Create one with: hats add <name>") }
            try context.pinToDock(targets, dedupeClaude: dedupeClaude)
        }
    }

    struct Unpin: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove launchers from the Dock (all profiles by default).")

        @Argument(help: "Profiles to unpin.")
        var names: [String] = []

        func run() throws {
            let context = Context()
            let launchers = LauncherBuilder(layout: context.layout)
            let bundles: [URL] =
                names.isEmpty
                ? try launchers.installed().map(\.bundle)
                : try names.compactMap { launchers.status(for: try context.profile($0).name)?.bundle }
            let changes = try DockEditor().unpin(bundles)
            if changes.isEmpty { print("No launchers were in the Dock.") }
            changes.forEach { print(Output.describe($0)) }
        }
    }
}
