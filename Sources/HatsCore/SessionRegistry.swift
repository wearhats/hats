import Foundation

/// One entry of Claude Code's live session registry, `<config>/sessions/<pid>.json`.
/// The file is internal to Claude Code, so every field except `pid` is optional
/// and unknown fields are ignored.
public struct RegisteredSession: Decodable, Equatable, Sendable {
    public let pid: Int32
    public let sessionId: String?
    public let cwd: String?
    public let startedAt: Double?
    public let procStart: String?
    public let version: String?
    public let kind: String?
    public let entrypoint: String?
    public let name: String?
    public let status: String?
    public let updatedAt: Double?

    public var startedAtDate: Date? { startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

public struct SessionRegistryReading: Sendable, Equatable {
    public var sessions: [RegisteredSession] = []
    public var undecodableFiles: [String] = []
}

public enum SessionRegistry {
    public static func read(configDir: URL) -> SessionRegistryReading {
        let dir = configDir.appending(path: "sessions", directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.plainPath) else {
            return SessionRegistryReading()
        }
        var reading = SessionRegistryReading()
        for name in names.sorted() where name.hasSuffix(".json") && Int32(name.dropLast(5)) != nil {
            let file = dir.appending(path: name, directoryHint: .notDirectory)
            do {
                reading.sessions.append(try JSONDecoder().decode(RegisteredSession.self, from: Data(contentsOf: file)))
            } catch {
                reading.undecodableFiles.append(file.plainPath)
            }
        }
        return reading
    }

    /// `procStart` is ctime-formatted in local time, e.g. "Tue Oct  7 20:15:31 2026".
    /// Whitespace is normalized because ctime pads single-digit days.
    public static func procStartMatches(_ procStart: String, startTime: Date, timeZone: TimeZone = .current) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return normalize(formatter.string(from: startTime)) == normalize(procStart)
    }

    private static func normalize(_ string: String) -> String {
        string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
