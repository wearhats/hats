import Darwin
import Foundation
import HatsCore

enum Output {
    static let useColor: Bool = isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    static func printTable(headers: [String], rows: [[String]]) {
        let widths = headers.indices.map { column in
            ([headers[column]] + rows.map { $0[column] }).map(\.count).max() ?? 0
        }
        // Not String.padding(toLength:): it counts UTF-16 units, so it would cut the end off a cell holding an emoji.
        func line(_ cells: [String]) -> String {
            zip(cells, widths).enumerated()
                .map { index, pair in index == cells.count - 1 ? pair.0 : pair.0 + String(repeating: " ", count: pair.1 - pair.0.count) }
                .joined(separator: "  ")
        }
        print(useColor ? "\u{1B}[1m\(line(headers))\u{1B}[0m" : line(headers))
        rows.forEach { print(line($0)) }
    }

    static func badge(_ level: Finding.Level) -> String {
        let (text, color) =
            switch level {
            case .ok: ("[ok]  ", "32")
            case .warn: ("[warn]", "33")
            case .fail: ("[fail]", "31")
            }
        return useColor ? "\u{1B}[\(color)m\(text)\u{1B}[0m" : text
    }

    static func age(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }

    static func printError(_ error: HatsError) {
        writeDiagnostic(label: "hats:", colorCode: "31", message: error.message, hint: error.hint)
    }

    /// Warnings go to stderr, so a command's stdout (and its `--json`) is unchanged.
    static func printWarning(_ message: String, hint: String) {
        writeDiagnostic(label: "hats: warning:", colorCode: "33", message: message, hint: hint)
    }

    private static func writeDiagnostic(label: String, colorCode: String, message: String, hint: String?) {
        let styledLabel = useColorOnStderr ? "\u{1B}[\(colorCode)m\(label)\u{1B}[0m" : label
        FileHandle.standardError.write(Data("\(styledLabel) \(message)\n".utf8))
        if let hint { FileHandle.standardError.write(Data("hint: \(hint)\n".utf8)) }
    }

    static let useColorOnStderr: Bool = isatty(STDERR_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
