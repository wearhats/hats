import Foundation

#if canImport(AppKit)
import AppKit
#endif

public protocol AppControl: Sendable {
    /// Launches `appURL` and returns the new process ID.
    func launch(appURL: URL, newInstance: Bool, arguments: [String], environment: [String: String]) async throws -> Int32
    /// Unhides and brings the app owning `pid` forward. `false` if it isn't a GUI app.
    @MainActor func activate(pid: Int32) -> Bool
    /// Whether `pid` is a regular (Dock-visible) application.
    @MainActor func isRegularApp(pid: Int32) -> Bool
    /// Asks the app owning `pid` to quit, as Cmd-Q would. `false` if it isn't
    /// a running app or refused.
    @MainActor func terminate(pid: Int32) -> Bool
}

#if canImport(AppKit)
public struct WorkspaceAppControl: AppControl {
    public init() {}

    public func launch(appURL: URL, newInstance: Bool, arguments: [String], environment: [String: String]) async throws -> Int32 {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = newInstance
        configuration.arguments = arguments
        configuration.environment = environment
        configuration.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        return app.processIdentifier
    }

    @MainActor
    public func activate(pid: Int32) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return false }
        app.unhide()
        return app.activate(from: .current, options: [.activateAllWindows]) || app.activate(options: [.activateAllWindows])
    }

    @MainActor
    public func isRegularApp(pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
    }

    @MainActor
    public func terminate(pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
    }
}
#endif

public enum OpenOutcome: Equatable, Sendable {
    case focused(pid: Int32)
    case launched(pid: Int32)
}

public struct DesktopLauncher: Sendable {
    let layout: Layout
    let processes: any ProcessTable
    let control: any AppControl
    let environment: [String: String]

    public init(
        layout: Layout,
        processes: any ProcessTable,
        control: any AppControl,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.layout = layout
        self.processes = processes
        self.control = control
        self.environment = environment
    }

    /// Focuses the profile's running Desktop instance, or launches one. Never
    /// starts a second instance on the same data dir: Desktop would happily
    /// run a duplicate.
    public func open(_ profile: Profile, among profiles: [Profile]) async throws -> OpenOutcome {
        if let instance = runningDesktops(of: profile, among: profiles).first {
            if await control.activate(pid: instance.pid) {
                return .focused(pid: instance.pid)
            }
            // The instance may have exited since the first scan, so only one
            // still running now blocks the launch. The stock app gets no data
            // dir argument, so launching it again cannot start a duplicate.
            let survivors = runningDesktops(of: profile, among: profiles)
            if !profile.isDefault, let survivor = survivors.first {
                throw HatsError(
                    .conflict,
                    "Claude for '\(profile.name)' is running (pid \(survivor.pid)) and could not be brought forward",
                    hint: survivors.count > 1
                        ? "run `hats dedupe` to quit the extra instances, then try again"
                        : "bring its window forward yourself, or quit Claude (Cmd-Q) and run `hats open \(profile.name)` again"
                )
            }
        }

        let app = try ClaudeApp.locate(layout: layout, environment: environment)
        if profile.isDefault {
            return .launched(pid: try await control.launch(appURL: app.url, newInstance: false, arguments: [], environment: [:]))
        }
        let pid = try await control.launch(
            appURL: app.url,
            newInstance: true,
            arguments: ["--user-data-dir=\(profile.desktopDir.plainPath)"],
            environment: ["CLAUDE_CONFIG_DIR": profile.codeDir.plainPath]
        )
        return .launched(pid: pid)
    }

    private func runningDesktops(of profile: Profile, among profiles: [Profile]) -> [Instance] {
        InstanceScanner(profiles: profiles, processes: processes).scan().instances
            .filter { $0.kind == .desktop && $0.profile == profile.name }
            .sorted { $0.startedAt < $1.startedAt }
    }
}

/// Finds the GUI app hosting a CLI session (terminal or IDE) by walking up
/// the parent chain.
public struct HostAppResolver: Sendable {
    let processes: any ProcessTable
    let control: any AppControl

    public init(processes: any ProcessTable, control: any AppControl) {
        self.processes = processes
        self.control = control
    }

    @MainActor
    public func hostApp(of pid: Int32) -> Int32? {
        let parents = Dictionary(processes.summaries().map { ($0.pid, $0.parentPID) }, uniquingKeysWith: { first, _ in first })
        var current: Int32? = pid
        var visited = Set<Int32>()
        while let candidate = current, candidate > 1, visited.insert(candidate).inserted {
            if control.isRegularApp(pid: candidate) { return candidate }
            current = parents[candidate]
        }
        return nil
    }
}
