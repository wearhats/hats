import Foundation

/// A validated profile identifier. It appears in filesystem paths, bundle IDs
/// and launcher scripts, so the allowed alphabet is deliberately tiny.
public struct ProfileName: Hashable, Comparable, Sendable, CustomStringConvertible, Codable {
    public static let `default` = ProfileName(unchecked: "default")
    public static let maxLength = 32

    public let rawValue: String

    public init(_ rawValue: String) throws(HatsError) {
        guard rawValue.wholeMatch(of: /[a-z0-9][a-z0-9-]{0,31}/) != nil else {
            throw HatsError(
                .usage,
                "invalid profile name '\(rawValue)'",
                hint: "use 1-32 characters: lowercase letters, digits and '-', starting with a letter or digit"
            )
        }
        self.rawValue = rawValue
    }

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        do {
            try self.init(raw)
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: error.message))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var isDefault: Bool { self == .default }

    /// `client-acme` becomes `Client Acme`.
    public var defaultLabel: String {
        rawValue.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    public var description: String { rawValue }

    /// `~/.claude-work` and `~/.claude.work` suggest `work`.
    public static func suggested(forConfigDir dir: URL) -> ProfileName? {
        let base = dir.lastPathComponent.lowercased().trimmingPrefix(".claude").drop { $0 == "-" || $0 == "." || $0 == "_" }
        guard let name = try? ProfileName(String(base)), !name.isDefault else { return nil }
        return name
    }

    public static func < (lhs: ProfileName, rhs: ProfileName) -> Bool { lhs.rawValue < rhs.rawValue }
}
