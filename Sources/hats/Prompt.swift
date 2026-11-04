import ArgumentParser
import Darwin
import Foundation
import HatsCore

enum Prompt {
    static var isInteractive: Bool { isatty(STDIN_FILENO) != 0 }

    /// Asks a yes/no question. Without a terminal it throws instead of
    /// guessing, unless the caller passed `--yes`.
    static func confirm(_ question: String, default defaultAnswer: Bool, assumeYes: Bool = false) throws -> Bool {
        if assumeYes { return true }
        guard isInteractive else {
            throw HatsError(.usage, "\(question) needs an answer", hint: "pass --yes when running non-interactively")
        }
        print("\(question) [\(defaultAnswer ? "Y/n" : "y/N")] ", terminator: "")
        switch readLine()?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "y", "yes": return true
        case "n", "no": return false
        default: return defaultAnswer
        }
    }

    static func ask(_ question: String, default defaultAnswer: String?) -> String {
        print("\(question)\(defaultAnswer.map { " [\($0)]" } ?? "") ", terminator: "")
        let answer = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        return answer.isEmpty ? defaultAnswer ?? "" : answer
    }
}

extension Context {
    func runningInstances(of profile: Profile) throws -> [Instance] {
        InstanceScanner(profiles: try readableProfiles(), processes: processes).scan().instances.filter { $0.profile == profile.name }
    }

    func refuseIfRunning(_ profile: Profile, action: String) throws {
        let running = try runningInstances(of: profile)
        guard running.isEmpty else {
            throw HatsError(
                .conflict,
                "profile '\(profile.name)' has \(running.count) running instance(s): pids \(running.map { String($0.pid) }.joined(separator: ", "))",
                hint: "quit them before you \(action)"
            )
        }
    }

    func open(_ profile: Profile) async throws {
        let launcher = DesktopLauncher(
            layout: layout, processes: processes, control: control, environment: environment, appSearch: touchpoints.appSearch)
        switch try await launcher.open(profile, among: try readableProfiles()) {
        case .focused(let pid): print("Focused Claude (\(profile.label)), pid \(pid).")
        case .launched(let pid): print("Launched Claude (\(profile.label)), pid \(pid).")
        }
    }

    func pinToDock(_ profiles: [Profile], dedupeClaude: Bool) throws {
        let bundles = try profiles.map { profile in
            guard let status = launchers.status(for: profile.name) else {
                throw HatsError(
                    .notFound, "no launcher for '\(profile.name)'", hint: "create it with: hats launcher rebuild \(profile.name)")
            }
            return status.bundle
        }
        let claude = dedupeClaude ? try ClaudeApp.locate(layout: layout, environment: environment, search: touchpoints.appSearch).url : nil
        for change in try dock.pin(bundles, dedupeClaude: claude) {
            print(Output.describe(change))
        }
    }

    func linkApplications() throws {
        let link = applicationsLink
        switch try link.link() {
        case .created: print("Linked \(link.url.plainPath) to \(link.launcherDir.plainPath). Finder's Applications folder now shows Hats.")
        case .alreadyLinked: print("\(link.url.plainPath) already links to \(link.launcherDir.plainPath).")
        case .notNeeded:
            print("No link needed: \(link.launcherDir.plainPath) is already inside \(link.applicationsDir.plainPath).")
        }
    }

    static let signInGuidance = """
        Sign in inside the new window. If the browser hands the login to another Claude window,
        quit the other Claude windows (Cmd-Q), sign in, then reopen them with: hats open --all
        """
}

extension Output {
    static func describe(_ change: DockChange) -> String {
        switch change {
        case .pinned(let url): "Pinned \(url.deletingPathExtension().lastPathComponent) to the Dock."
        case .alreadyPinned(let url): "\(url.deletingPathExtension().lastPathComponent) is already in the Dock."
        case .repaired(let url): "Repaired the Dock tile for \(url.deletingPathExtension().lastPathComponent)."
        case .unpinned(let url): "Removed \(url.deletingPathExtension().lastPathComponent) from the Dock."
        case .removedDuplicateClaude(let count): "Removed \(count) duplicate Claude.app tile(s) from the Dock."
        }
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
