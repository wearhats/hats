import Foundation

public struct ProfileColor: Hashable, Sendable, Codable, CustomStringConvertible {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    /// Material 700 tones: distinct from each other and dark enough for a white glyph.
    /// The order is part of `automatic(for:)`, so new names go at the end.
    public static let named: [(name: String, color: ProfileColor)] = [
        ("blue", "#1565C0"), ("green", "#2E7D32"), ("red", "#C62828"), ("purple", "#6A1B9A"),
        ("orange", "#BF360C"), ("teal", "#00695C"), ("pink", "#AD1457"), ("brown", "#4E342E"),
    ]

    public static let palette: [ProfileColor] = named.map(\.color)

    public static let accepted = named.map(\.name).joined(separator: ", ") + " or #RRGGBB"

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: String) throws(HatsError) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            throw HatsError(.usage, "invalid color '\(hex)'", hint: "use #RRGGBB, for example #2E7D32")
        }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    /// A palette name, ignoring case, or `#RRGGBB`.
    public init(parsing value: String) throws(HatsError) {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        if let match = Self.named.first(where: { $0.name == trimmed }) {
            self = match.color
            return
        }
        do {
            try self.init(hex: trimmed)
        } catch {
            throw HatsError(.usage, "invalid color '\(value)'", hint: "use \(Self.accepted)")
        }
    }

    /// Stable across runs and machines, unlike `hashValue`.
    public static func automatic(for name: ProfileName) -> ProfileColor {
        var hash: UInt32 = 2_166_136_261
        for byte in name.rawValue.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return palette[Int(hash % UInt32(palette.count))]
    }

    /// WCAG relative luminance, used to pick a readable glyph colour.
    public var relativeLuminance: Double {
        func channel(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.039_28 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    public var prefersDarkGlyph: Bool { relativeLuminance > 0.179 }

    public var description: String { String(format: "#%02X%02X%02X", red, green, blue) }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        do {
            try self.init(hex: raw)
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: error.message))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension ProfileColor: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        try! self.init(hex: value)
    }
}

/// The glyph on a profile's launcher icon. A letter tells many profiles apart;
/// the two pictures make the common work/personal pair recognisable at a glance.
public enum LauncherIcon: String, Codable, CaseIterable, Sendable {
    case letter, briefcase, person

    public static func automatic(for name: ProfileName) -> LauncherIcon {
        switch name.rawValue {
        case "work", "job", "company", "corp", "office": .briefcase
        case "personal", "private", "home", "me": .person
        default: .letter
        }
    }
}

public struct ProfileMetadata: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var label: String
    public var color: ProfileColor
    public var createdAt: Date
    /// Set when the profile adopts an existing `CLAUDE_CONFIG_DIR` (such as
    /// `~/.claude-work`) instead of owning one. hats never deletes it.
    public var externalCodeDir: String?
    /// Absent in profiles written before icons existed; they keep the letter.
    public var icon: LauncherIcon?

    public init(label: String, color: ProfileColor, createdAt: Date, externalCodeDir: String? = nil, icon: LauncherIcon? = nil) {
        schemaVersion = Self.currentSchemaVersion
        self.label = label
        self.color = color
        self.createdAt = createdAt
        self.externalCodeDir = externalCodeDir
        self.icon = icon
    }
}

public struct Profile: Equatable, Sendable {
    public let name: ProfileName
    public let label: String
    public let color: ProfileColor
    public let desktopDir: URL
    public let codeDir: URL
    public let createdAt: Date?
    public let codeDirIsExternal: Bool
    public var icon: LauncherIcon = .letter

    public var isDefault: Bool { name.isDefault }

    /// The letter shown on a `.letter` icon.
    public var initial: String {
        String(label.first(where: { $0.isLetter || $0.isNumber }) ?? "?").uppercased()
    }
}
