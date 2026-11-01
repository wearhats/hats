import Foundation

#if canImport(AppKit)
import AppKit
#endif

public struct ClaudeApp: Equatable, Sendable {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"

    public let url: URL
    public let version: String?

    /// Resolution order: `HATS_CLAUDE_APP`, Launch Services by bundle ID, then
    /// the two conventional install locations. Resolved on every launch so a
    /// moved or reinstalled app keeps working.
    public static func locate(
        layout: Layout,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        lookUpBundleID: (String) -> URL? = ClaudeApp.systemBundleLookup
    ) throws(HatsError) -> ClaudeApp {
        let fm = FileManager.default
        if let override = environment["HATS_CLAUDE_APP"], !override.isEmpty {
            let url = URL(filePath: override, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: url.plainPath) else {
                throw HatsError(.environment, "HATS_CLAUDE_APP points to a missing app: \(override)")
            }
            return ClaudeApp(url: url, version: version(of: url))
        }
        let candidates = [
            lookUpBundleID(bundleIdentifier),
            URL(filePath: "/Applications/Claude.app", directoryHint: .isDirectory),
            layout.home.appending(path: "Applications/Claude.app", directoryHint: .isDirectory),
        ]
        for case let url? in candidates where fm.fileExists(atPath: url.plainPath) {
            return ClaudeApp(url: url, version: version(of: url))
        }
        throw HatsError(.environment, "Claude Desktop is not installed", hint: "install it from https://claude.com/download")
    }

    #if canImport(AppKit)
    public static let systemBundleLookup: @Sendable (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    #else
    public static let systemBundleLookup: @Sendable (String) -> URL? = { _ in nil }
    #endif

    static func version(of appURL: URL) -> String? {
        let plist = appURL.appending(path: "Contents/Info.plist", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: plist),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }
}

/// Locates an executable on `PATH`, honouring an explicit override.
public enum ExecutableLocator {
    public static func find(
        _ name: String,
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let fm = FileManager.default
        if let override, !override.isEmpty {
            return fm.isExecutableFile(atPath: override) ? URL(filePath: override) : nil
        }
        if name.contains("/") {
            return fm.isExecutableFile(atPath: name) ? URL(filePath: name) : nil
        }
        let path = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in path.split(separator: ":") where !dir.isEmpty {
            let candidate = URL(filePath: String(dir), directoryHint: .isDirectory).appending(path: name)
            if fm.isExecutableFile(atPath: candidate.plainPath) { return candidate }
        }
        return nil
    }
}
