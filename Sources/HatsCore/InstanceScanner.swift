import Foundation

public enum InstanceKind: String, Codable, Sendable, CaseIterable {
    case desktop
    case desktopCode = "desktop-code"
    case cli
    case ide
    case sdk
    case other

    init(entrypoint: String?) {
        let value = entrypoint?.lowercased() ?? ""
        switch true {
        case value == "cli": self = .cli
        case value.contains("desktop"): self = .desktopCode
        case value.contains("vscode"), value.contains("jetbrains"), value.contains("ide"): self = .ide
        case value.hasPrefix("sdk"): self = .sdk
        case value.isEmpty: self = .cli
        default: self = .other
        }
    }
}

public struct Instance: Codable, Equatable, Sendable {
    /// `nil` when the instance runs with a data dir hats doesn't know.
    public let profile: ProfileName?
    public let kind: InstanceKind
    public let pid: Int32
    public let startedAt: Date
    public let status: String?
    public let name: String?
    public let cwd: String?
    public let sessionId: String?
    public let version: String?
    /// The Desktop `--user-data-dir` or CLI `CLAUDE_CONFIG_DIR` the process runs with.
    public let dataDir: String
    /// Desktop only: the `CLAUDE_CONFIG_DIR` handed to it, `nil` when absent.
    public let configDir: String?

    /// Part of the `--json` contract: a missing value prints as `null`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encode(kind, forKey: .kind)
        try container.encode(pid, forKey: .pid)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(status, forKey: .status)
        try container.encode(name, forKey: .name)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(version, forKey: .version)
        try container.encode(dataDir, forKey: .dataDir)
        try container.encode(configDir, forKey: .configDir)
    }
}

public struct InstanceScan: Sendable {
    public var instances: [Instance]
    public var undecodableRegistryFiles: [String]
}

public struct InstanceScanner: Sendable {
    static let desktopExecutableSuffix = "/Contents/MacOS/Claude"
    /// Long-running `claude` helpers that aren't sessions.
    static let helperFlags: Set<String> = ["--chrome-native-host", "mcp", "--version", "-v"]
    /// How far a registry's `startedAt` may sit from the kernel's start time:
    /// Claude Code writes it once it has booted, a moment after exec.
    static let startedAtWindow: ClosedRange<TimeInterval> = -2...30

    let profiles: [Profile]
    let processes: any ProcessTable

    public init(profiles: [Profile], processes: any ProcessTable) {
        self.profiles = profiles
        self.processes = processes
    }

    public func scan() -> InstanceScan {
        let summaries = processes.summaries()
        let byPID = Dictionary(summaries.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let cliProcesses = cliProcessConfigDirs(summaries)

        // Registries live in every config dir in use: managed profiles plus
        // any unmanaged dir a running process points at.
        var configDirs = profiles.map(\.codeDir.canonicalPath)
        for dir in cliProcesses.values.sorted() where !configDirs.contains(dir) { configDirs.append(dir) }

        var instances = desktopInstances(summaries)
        var registered = Set<Int32>()
        var undecodable: [String] = []
        for dir in configDirs {
            let reading = SessionRegistry.read(configDir: URL(filePath: dir, directoryHint: .isDirectory))
            undecodable += reading.undecodableFiles
            for session in reading.sessions where !registered.contains(session.pid) {
                guard cliProcesses[session.pid] != nil, let process = byPID[session.pid],
                    Self.isSameProcess(session, startTime: process.startTime)
                else { continue }
                registered.insert(session.pid)
                instances.append(
                    Instance(
                        profile: profile(forConfigDir: dir),
                        kind: InstanceKind(entrypoint: session.entrypoint),
                        pid: session.pid,
                        startedAt: session.startedAtDate ?? process.startTime,
                        status: session.status,
                        name: session.name,
                        cwd: session.cwd,
                        sessionId: session.sessionId,
                        version: session.version,
                        dataDir: dir,
                        configDir: nil
                    ))
            }
        }

        for (pid, dir) in cliProcesses where !registered.contains(pid) {
            guard let process = byPID[pid] else { continue }
            instances.append(
                Instance(
                    profile: profile(forConfigDir: dir),
                    kind: .cli,
                    pid: pid,
                    startedAt: process.startTime,
                    status: nil,
                    name: nil,
                    cwd: nil,
                    sessionId: nil,
                    version: nil,
                    dataDir: dir,
                    configDir: nil
                ))
        }
        instances.sort(by: Self.displayOrder)
        return InstanceScan(instances: instances, undecodableRegistryFiles: undecodable)
    }

    /// Registry files outlive their process and macOS reuses PIDs, so an entry
    /// counts only if its start time matches the live process. `startedAt`
    /// (epoch ms) wins over `procStart`, a local-time string that stops
    /// matching after a time-zone change.
    static func isSameProcess(_ session: RegisteredSession, startTime: Date) -> Bool {
        if let startedAt = session.startedAtDate {
            return startedAtWindow.contains(startedAt.timeIntervalSince(startTime))
        }
        if let procStart = session.procStart {
            return SessionRegistry.procStartMatches(procStart, startTime: startTime)
        }
        return false
    }

    private func profile(forConfigDir canonicalDir: String) -> ProfileName? {
        profiles.first { $0.codeDir.canonicalPath == canonicalDir }?.name
    }

    private func desktopInstances(_ summaries: [ProcessSummary]) -> [Instance] {
        summaries.filter { $0.command == "Claude" }.compactMap { process in
            guard let details = processes.details(of: process.pid),
                details.executablePath.hasSuffix(Self.desktopExecutableSuffix),
                details.argumentValue("--type") == nil
            else { return nil }
            let dataDir =
                details.argumentValue("--user-data-dir").map { URL(filePath: $0) }
                ?? profiles.first(where: \.isDefault)?.desktopDir
            let dataPath = dataDir?.canonicalPath ?? ""
            return Instance(
                profile: profiles.first { $0.desktopDir.canonicalPath == dataPath }?.name,
                kind: .desktop,
                pid: process.pid,
                startedAt: process.startTime,
                status: nil,
                name: nil,
                cwd: nil,
                sessionId: nil,
                version: nil,
                dataDir: dataPath,
                configDir: details.claudeConfigDir
            )
        }
    }

    /// Canonical config dir of every running Claude Code session process.
    private func cliProcessConfigDirs(_ summaries: [ProcessSummary]) -> [Int32: String] {
        let defaultCode = profiles.first(where: \.isDefault)?.codeDir
        var result: [Int32: String] = [:]
        for process in summaries where Self.mayBeClaudeCLI(process) {
            guard let details = processes.details(of: process.pid),
                Self.isClaudeCLI(details),
                !details.arguments.dropFirst().contains(where: Self.helperFlags.contains),
                let configDir = details.claudeConfigDir.map({ URL(filePath: $0) }) ?? defaultCode
            else { continue }
            result[process.pid] = configDir.canonicalPath
        }
        return result
    }

    /// The native installer runs `~/.local/share/claude/versions/<version>`, so
    /// the kernel's process name is often the version string, not "claude".
    static func mayBeClaudeCLI(_ process: ProcessSummary) -> Bool {
        process.command == "claude" || process.command.wholeMatch(of: /\d+\.\d+\.\d+.*/) != nil
    }

    static func isClaudeCLI(_ details: ProcessDetails) -> Bool {
        let argv0 = details.arguments.first.map { URL(filePath: $0).lastPathComponent }
        return argv0 == "claude" || details.executablePath.contains("/claude/versions/")
    }

    static func displayOrder(_ lhs: Instance, _ rhs: Instance) -> Bool {
        let left = (lhs.profile.map { $0.isDefault ? "" : $0.rawValue } ?? "~", lhs.kind != .desktop, lhs.startedAt)
        let right = (rhs.profile.map { $0.isDefault ? "" : $0.rawValue } ?? "~", rhs.kind != .desktop, rhs.startedAt)
        if left.0 != right.0 { return left.0 < right.0 }
        if left.1 != right.1 { return !left.1 }
        return left.2 < right.2
    }
}
