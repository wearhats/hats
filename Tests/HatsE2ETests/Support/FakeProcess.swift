import Foundation

struct FakeBinaryNotFound: Error, CustomStringConvertible {
    let path: String
    var description: String { "no hats-e2e-fake at \(path). Run swift build." }
}

struct FakeNotReady: Error, CustomStringConvertible {
    var output: String
    var stderr = ""
    var description: String { "the fake never said it was ready.\nstdout: \(output)\nstderr: \(stderr)" }
}

/// A running fake Claude. Ready means `ready <pid>` was read, so a test never
/// sleeps. It exits when its stdin closes, on `stop()`, when its sandbox goes away,
/// or when the test process dies.
final class FakeProcess {
    private static let stopTimeoutSeconds: TimeInterval = 5

    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private var readyPIDs: [Int32] = []
    /// `sandbox-exec` keeps its PID through exec, so this is the fake's own.
    var pid: Int32 { process.processIdentifier }
    /// The child started through `HATS_FAKE_SPAWN`. The two print `ready` in either order.
    var childPID: Int32? { readyPIDs.first { $0 != pid } }
    private var stopped = false

    fileprivate init(executable: String, arguments: [String], environment: [String: String], sandboxRoot: String, readyLines: Int) throws {
        let wrapped = try SeatbeltGuard.wrap(executable: executable, arguments: arguments, sandboxRoot: sandboxRoot)
        process.executableURL = URL(filePath: wrapped.executable)
        process.arguments = wrapped.arguments
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        do {
            readyPIDs = try waitForReady(lines: readyLines)
        } catch var error as FakeNotReady {
            stop()
            error.stderr = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw error
        }
    }

    deinit { stop() }

    /// Closes stdin and waits, so the fake and any child are gone from the table on
    /// return. A wedged fake gets killed rather than hanging the whole test run.
    func stop() {
        guard !stopped, process.processIdentifier != 0 else { return }
        stopped = true
        try? stdin.fileHandleForWriting.close()
        let deadline = Date.now.addingTimeInterval(Self.stopTimeoutSeconds)
        while process.isRunning, Date.now < deadline { usleep(5_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }

    private func waitForReady(lines wanted: Int, timeoutSeconds: TimeInterval = 10) throws -> [Int32] {
        let descriptor = stdout.fileHandleForReading.fileDescriptor
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        var output = Data()
        var ready: [Int32] = []
        while ready.count < wanted {
            guard Date.now < deadline else { throw FakeNotReady(output: String(decoding: output, as: UTF8.self)) }
            var polled = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&polled, 1, 50) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 1_024)
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { throw FakeNotReady(output: String(decoding: output, as: UTF8.self)) }
            output.append(contentsOf: buffer[..<count])
            ready =
                String(decoding: output, as: UTF8.self).split(separator: "\n")
                .compactMap { $0.hasPrefix("ready ") ? Int32($0.dropFirst(6)) : nil }
        }
        return ready
    }
}

struct ProbeFailed: Error, CustomStringConvertible {
    let result: CommandResult
    var description: String { "the probe didn't finish:\n\(result)" }
}

enum FakeBinary {
    /// The status a `HATS_FAKE_PROBE` call returned, under the guard when given a sandbox.
    static func probe(_ probe: String, guardedBy sandbox: E2ESandbox? = nil) throws -> String {
        let fake = try path()
        let environment = ["HATS_FAKE_PROBE": probe]
        let result =
            try sandbox?.guarded(fake, [], environment: environment)
            ?? CommandRunner.run(executable: fake, arguments: [], environment: environment)
        guard result.exit == 0, !result.wasKilledBySignal else { throw ProbeFailed(result: result) }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Always the one next to the test bundle, whichever hats binary is under test.
    static func path() throws -> String {
        let path = BuiltProduct.path(named: "hats-e2e-fake")
        guard FileManager.default.isExecutableFile(atPath: path) else { throw FakeBinaryNotFound(path: path) }
        return path
    }
}

extension E2ESandbox {
    /// How hats reports an existing dir. It resolves symlinks with `URL`, which
    /// drops the `/private` of a temp dir; a real HOME has no such prefix.
    func reported(_ path: String) -> String {
        path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }

    /// Copies the fake to `relativePath`, which decides its kernel name and path.
    func installFake(at relativePath: String) throws -> String {
        let path = "\(root)/\(relativePath)"
        if !exists(path) {
            try makeDirectory((path as NSString).deletingLastPathComponent)
            try FileManager.default.copyItem(atPath: try FakeBinary.path(), toPath: path)
        }
        return path
    }

    func startFake(
        at relativePath: String, arguments: [String] = [], environment overrides: [String: String] = [:], readyLines: Int = 1
    ) throws -> FakeProcess {
        // Where a real process keeps an API key. hats must skip it undecoded.
        let base = environment.merging(["ANTHROPIC_API_KEY": sentinel]) { _, new in new }
        let fake = try FakeProcess(
            executable: try installFake(at: relativePath), arguments: arguments,
            environment: base.merging(overrides) { _, new in new }, sandboxRoot: root, readyLines: readyLines)
        fakes.append(fake)
        return fake
    }

    /// A Claude Code session under the kernel name `claude`.
    func startCLI(
        configDir: String?, session: String? = nil, timestamps: String = "both", stale: Int = 0, arguments: [String] = []
    ) throws -> FakeProcess {
        var overrides = ["HATS_FAKE_TIMESTAMPS": timestamps, "HATS_FAKE_STALE": String(stale)]
        if let configDir { overrides["CLAUDE_CONFIG_DIR"] = configDir }
        if let session { overrides["HATS_FAKE_SESSION"] = session }
        return try startFake(at: "bin/claude", arguments: arguments, environment: overrides)
    }

    /// A Desktop main process, run from inside a `.app` as the real one is. Its
    /// `CLAUDE_CONFIG_DIR` is the profile's unless `configDir` says otherwise, and
    /// `.some(nil)` leaves it out.
    func startDesktop(
        profile: String? = nil, userDataDir: String? = nil, configDir: String?? = nil, arguments: [String] = []
    ) throws -> FakeProcess {
        var argv = arguments
        if let dir = profile.map({ "\(profileDir($0))/desktop" }) ?? userDataDir { argv.insert("--user-data-dir=\(dir)", at: 0) }
        var overrides: [String: String] = [:]
        if let dir = configDir ?? profile.map({ "\(profileDir($0))/code" }) { overrides["CLAUDE_CONFIG_DIR"] = dir }
        return try startFake(at: "apps/Claude.app/Contents/MacOS/Claude", arguments: argv, environment: overrides)
    }
}
