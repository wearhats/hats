import Foundation

#if os(macOS)
import Darwin
#endif

public struct ProcessSummary: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let startTime: Date
    /// Kernel `p_comm`: the executable name, truncated to 16 bytes.
    public let command: String

    public init(pid: Int32, parentPID: Int32, startTime: Date, command: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.startTime = startTime
        self.command = command
    }
}

/// What hats keeps of another process. Of its environment, which often holds
/// API keys, only `CLAUDE_CONFIG_DIR` is kept: it says which Claude Code config
/// dir a Desktop or CLI process uses, and nothing else in hats needs the rest.
public struct ProcessDetails: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let claudeConfigDir: String?

    public init(executablePath: String, arguments: [String], claudeConfigDir: String?) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.claudeConfigDir = claudeConfigDir
    }

    /// Value of `--flag=value` or `--flag value`, last occurrence wins like Chromium.
    public func argumentValue(_ flag: String) -> String? {
        var value: String?
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            if argument.hasPrefix(flag + "=") {
                value = String(argument.dropFirst(flag.count + 1))
            } else if argument == flag {
                value = iterator.next()
            }
        }
        return value
    }
}

public protocol ProcessTable: Sendable {
    func summaries() -> [ProcessSummary]
    /// `nil` when the process is gone or belongs to another user.
    func details(of pid: Int32) -> ProcessDetails?
}

#if os(macOS)
public struct DarwinProcessTable: ProcessTable {
    public init() {}

    public func summaries() -> [ProcessSummary] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return [] }
        // The table can grow between the two calls.
        size += size / 8
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        return buffer.prefix(count).map(Self.summary)
    }

    public func details(of pid: Int32) -> ProcessDetails? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return ProcArgsParser.parse(Array(buffer.prefix(size)))
    }

    private static func summary(_ info: kinfo_proc) -> ProcessSummary {
        var comm = info.kp_proc.p_comm
        let command = withUnsafeBytes(of: &comm) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let start = info.kp_proc.p_un.__p_starttime
        return ProcessSummary(
            pid: info.kp_proc.p_pid,
            parentPID: info.kp_eproc.e_ppid,
            startTime: Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000),
            command: command
        )
    }
}
#endif

/// Decodes the `KERN_PROCARGS2` layout:
/// `argc (Int32) | exec_path NUL | NUL padding | argv[0..argc) NUL-separated | env NUL-separated`.
/// Environment entries other than `CLAUDE_CONFIG_DIR` are skipped as raw
/// bytes, never decoded or stored.
public enum ProcArgsParser {
    static let configDirPrefix = Array("CLAUDE_CONFIG_DIR=".utf8)

    public static func parse(_ bytes: [UInt8]) -> ProcessDetails? {
        let intSize = MemoryLayout<Int32>.size
        guard bytes.count > intSize else { return nil }
        let argc = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc >= 0 else { return nil }

        var index = intSize
        func nextString() -> String? {
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            let string = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            return string
        }
        func skipNULs() {
            while index < bytes.count, bytes[index] == 0 { index += 1 }
        }

        guard let executablePath = nextString() else { return nil }
        skipNULs()
        var arguments: [String] = []
        for _ in 0..<argc {
            guard let argument = nextString() else { return nil }
            arguments.append(argument)
        }
        var claudeConfigDir: String?
        while index < bytes.count, bytes[index] != 0 {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            let entry = bytes[start..<index]
            index += 1
            if claudeConfigDir == nil, entry.starts(with: configDirPrefix) {
                claudeConfigDir = String(decoding: entry.dropFirst(configDirPrefix.count), as: UTF8.self)
            }
        }
        return ProcessDetails(executablePath: executablePath, arguments: arguments, claudeConfigDir: claudeConfigDir)
    }
}
