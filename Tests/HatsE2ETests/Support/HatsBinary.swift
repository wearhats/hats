import Foundation

struct HatsBinaryNotFound: Error, CustomStringConvertible {
    let path: String

    var description: String {
        "no executable hats at \(path). Run swift build, or point HATS_E2E_BINARY at the binary to test."
    }
}

/// Products of this package's own build, next to the test bundle.
enum BuiltProduct {
    private final class BundleAnchor {}

    static func path(named name: String) -> String {
        Bundle(for: BundleAnchor.self).bundleURL.deletingLastPathComponent().appending(path: name).path(percentEncoded: false)
    }
}

enum HatsBinary {
    static func path() throws -> String {
        let path: String
        if let override = ProcessInfo.processInfo.environment["HATS_E2E_BINARY"], !override.isEmpty {
            path = URL(filePath: override).standardizedFileURL.path(percentEncoded: false)
        } else {
            path = BuiltProduct.path(named: "hats")
        }
        guard FileManager.default.isExecutableFile(atPath: path) else { throw HatsBinaryNotFound(path: path) }
        return path
    }
}
