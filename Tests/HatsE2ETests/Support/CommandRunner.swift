import Foundation

struct CommandResult: CustomStringConvertible, Sendable {
    let command: [String]
    let pid: Int32
    let exit: Int32
    let wasKilledBySignal: Bool
    let stdout: String
    let stderr: String

    var description: String {
        """
        command: \(command.joined(separator: " "))
        exit: \(exit)\(wasKilledBySignal ? " (killed by signal)" : "")
        stdout: \(stdout.isEmpty ? "<empty>" : stdout)
        stderr: \(stderr.isEmpty ? "<empty>" : stderr)
        """
    }
}

struct CommandTimedOut: Error, CustomStringConvertible {
    let command: [String]
    let seconds: Int
    let stdout: String
    let stderr: String

    var description: String {
        "timed out after \(seconds) s: \(command.joined(separator: " "))\nstdout: \(stdout)\nstderr: \(stderr)"
    }
}

enum CommandRunner {
    static let defaultTimeoutSeconds = 10

    /// Stdin is /dev/null, so anything that prompts takes its no-terminal path
    /// and a hang fails on the timeout instead of waiting for a person.
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL? = nil,
        timeoutSeconds: Int = defaultTimeoutSeconds
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let pid = process.processIdentifier
        let command = [executable] + arguments

        var output = OutputDrain(stdout: stdoutPipe, stderr: stderrPipe)
        let deadline = Date.now.addingTimeInterval(TimeInterval(timeoutSeconds))
        var hasExited = false
        while !output.isFinished(hasExited: hasExited) {
            if !hasExited { hasExited = exited.wait(timeout: .now()) == .success }
            guard Date.now < deadline else {
                kill(pid, SIGKILL)
                exited.wait()
                throw CommandTimedOut(command: command, seconds: timeoutSeconds, stdout: output.stdout, stderr: output.stderr)
            }
        }
        if !hasExited { exited.wait() }
        return CommandResult(
            command: command,
            pid: pid,
            exit: process.terminationStatus,
            wasKilledBySignal: process.terminationReason == .uncaughtSignal,
            stdout: output.stdout,
            stderr: output.stderr
        )
    }
}

/// Reads on the test's own thread, as data arrives. A background reader blocked
/// on EOF lost all output once tests ran in parallel (measured), and anything
/// still holding a pipe's write end must not be able to stall a test.
private struct OutputDrain {
    private var descriptors: [Int32]
    private var collected: [Int32: Data] = [:]
    private let stdoutDescriptor: Int32
    private let stderrDescriptor: Int32

    init(stdout: Pipe, stderr: Pipe) {
        stdoutDescriptor = stdout.fileHandleForReading.fileDescriptor
        stderrDescriptor = stderr.fileHandleForReading.fileDescriptor
        descriptors = [stdoutDescriptor, stderrDescriptor]
    }

    var stdout: String { String(decoding: collected[stdoutDescriptor] ?? Data(), as: UTF8.self) }
    var stderr: String { String(decoding: collected[stderrDescriptor] ?? Data(), as: UTF8.self) }

    /// Finished at EOF on both pipes, or once the process is gone and nothing
    /// is left to read.
    mutating func isFinished(hasExited: Bool) -> Bool {
        var polled = descriptors.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
        let ready = poll(&polled, nfds_t(polled.count), hasExited ? 0 : 10)
        if ready == 0 { return hasExited || descriptors.isEmpty }
        for entry in polled where entry.revents != 0 {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = read(entry.fd, &buffer, buffer.count)
            if count > 0 {
                collected[entry.fd, default: Data()].append(contentsOf: buffer[..<count])
            } else {
                descriptors.removeAll { $0 == entry.fd }
            }
        }
        return descriptors.isEmpty
    }
}
