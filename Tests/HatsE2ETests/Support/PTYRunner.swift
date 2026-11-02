import Darwin
import Testing
import Foundation

struct PTYStep: Sendable {
    let expect: String
    let send: String

    /// Waits for `expect` in new output, then types `send` and Return.
    init(_ expect: String, send: String = "") {
        self.expect = expect
        self.send = send
    }
}

struct PTYTimedOut: Error, CustomStringConvertible {
    let waitingFor: String
    let transcript: String
    var description: String { "timed out waiting for \(waitingFor). Transcript:\n\(transcript)" }
}

struct PTYEndedEarly: Error, CustomStringConvertible {
    let waitingFor: String
    let result: PTYResult
    var description: String { "the program ended while a step still waited for '\(waitingFor)'.\n\(result)" }
}

struct PTYResult: CustomStringConvertible {
    let exit: Int32
    let wasKilledBySignal: Bool
    /// What a person would see, with the terminal's CRLF back to LF.
    let transcript: String
    var description: String { "exit: \(exit)\(wasKilledBySignal ? " (killed by signal)" : "")\n\(transcript)" }
}

/// Runs a command on a real pseudo-terminal, so `isatty` is true and prompts ask
/// instead of refusing. Echo is off, so a transcript holds only the program's output.
enum PTYRunner {
    static func run(
        executable: String, arguments: [String], environment: [String: String], workingDirectory: String, steps: [PTYStep]
    ) throws -> PTYResult {
        var primary: Int32 = 0
        var replica: Int32 = 0
        guard openpty(&primary, &replica, nil, nil, nil) == 0 else { throw POSIXError(.ENXIO) }
        defer { close(primary) }
        var settings = termios()
        tcgetattr(replica, &settings)
        settings.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(replica, TCSANOW, &settings)

        let terminal = FileHandle(fileDescriptor: replica, closeOnDealloc: true)
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(filePath: workingDirectory, directoryHint: .isDirectory)
        process.standardInput = terminal
        process.standardOutput = terminal
        process.standardError = terminal
        try process.run()
        // Holding this open would keep the primary from ever seeing the end of output.
        try terminal.close()

        var output = Data()
        var consumed = 0
        var remaining = steps[...]
        let deadline = Date.now.addingTimeInterval(TimeInterval(CommandRunner.defaultTimeoutSeconds))

        func giveUp(waitingFor: String) -> PTYTimedOut {
            // Checked first: once reaped, this PID could belong to anything.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return PTYTimedOut(waitingFor: waitingFor, transcript: decode(output))
        }

        var reachedEnd = false
        while !reachedEnd {
            if let step = remaining.first, let range = output[consumed...].range(of: Data(step.expect.utf8)) {
                consumed = range.upperBound
                remaining.removeFirst()
                let line = Data((step.send + "\n").utf8)
                _ = line.withUnsafeBytes { write(primary, $0.baseAddress, $0.count) }
                continue
            }
            guard Date.now < deadline else {
                throw giveUp(waitingFor: remaining.first.map { "'\($0.expect)'" } ?? "the end of output")
            }
            let hasExited = !process.isRunning
            var polled = pollfd(fd: primary, events: Int16(POLLIN), revents: 0)
            guard poll(&polled, 1, hasExited ? 0 : 50) > 0 else {
                // Anything that outlives the program and holds the terminal must not
                // be able to stall a test.
                reachedEnd = hasExited
                continue
            }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            let count = read(primary, &buffer, buffer.count)
            if count > 0 {
                output.append(contentsOf: buffer[..<count])
            } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
                reachedEnd = true
            }
        }
        while process.isRunning {
            guard Date.now < deadline else { throw giveUp(waitingFor: "the program to exit") }
            usleep(5_000)
        }
        process.waitUntilExit()
        let result = PTYResult(
            exit: process.terminationStatus, wasKilledBySignal: process.terminationReason == .uncaughtSignal, transcript: decode(output))
        if let unmet = remaining.first { throw PTYEndedEarly(waitingFor: unmet.expect, result: result) }
        return result
    }

    private static func decode(_ output: Data) -> String {
        String(decoding: output, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
    }
}

extension E2ESandbox {
    /// Runs hats on a terminal, under the same guard and sentinel check as `hats()`.
    func hatsOnTerminal(
        _ arguments: [String], steps: [PTYStep] = [], environment overrides: [String: String] = [:], removing removed: Set<String> = [],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> PTYResult {
        let wrapped = try SeatbeltGuard.wrap(executable: try HatsBinary.path(), arguments: arguments, sandboxRoot: root)
        let result = try PTYRunner.run(
            executable: wrapped.executable, arguments: wrapped.arguments, environment: processEnvironment(overrides, removing: removed),
            workingDirectory: root, steps: steps)
        if result.transcript.contains(sentinel) || eventLogText.contains(sentinel) {
            Issue.record("A planted secret reached the output.\n\(result)", sourceLocation: sourceLocation)
        }
        return result
    }
}
