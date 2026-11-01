import Foundation

struct HatsBinaryNotFound: Error, CustomStringConvertible {
    let path: String

    var description: String {
        "no executable hats at \(path). Run swift build, or point HATS_E2E_BINARY at the binary to test."
    }
}

enum HatsBinary {
    private final class BundleAnchor {}

    static func path() throws -> String {
        let path: String
        if let override = ProcessInfo.processInfo.environment["HATS_E2E_BINARY"], !override.isEmpty {
            path = URL(filePath: override).standardizedFileURL.path(percentEncoded: false)
        } else {
            path = Bundle(for: BundleAnchor.self).bundleURL.deletingLastPathComponent().appending(path: "hats").path(percentEncoded: false)
        }
        guard FileManager.default.isExecutableFile(atPath: path) else { throw HatsBinaryNotFound(path: path) }
        return path
    }
}
