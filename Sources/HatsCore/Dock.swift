import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// The Dock's `persistent-apps` list. Behind a protocol so tests never touch
/// the real Dock.
public protocol DockPreferences: Sendable {
    func persistentApps() -> [[String: Any]]
    func setPersistentApps(_ apps: [[String: Any]]) throws(HatsError)
    /// The Dock only rereads its preferences when it restarts.
    func restartDock()
}

#if canImport(AppKit)
/// Goes through CFPreferences rather than editing the plist file, so
/// cfprefsd's cache can't overwrite the change.
public struct SystemDockPreferences: DockPreferences {
    static var domain: CFString { "com.apple.dock" as CFString }
    static var key: CFString { "persistent-apps" as CFString }

    public init() {}

    public func persistentApps() -> [[String: Any]] {
        CFPreferencesCopyAppValue(Self.key, Self.domain) as? [[String: Any]] ?? []
    }

    public func setPersistentApps(_ apps: [[String: Any]]) throws(HatsError) {
        CFPreferencesSetAppValue(Self.key, apps as CFArray, Self.domain)
        guard CFPreferencesAppSynchronize(Self.domain) else {
            throw HatsError(.io, "cannot save the Dock preferences")
        }
    }

    public func restartDock() {
        for dock in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock") {
            kill(dock.processIdentifier, SIGTERM)
        }
    }
}
#endif

public enum DockChange: Equatable, Sendable {
    case pinned(URL)
    case alreadyPinned(URL)
    case repaired(URL)
    case unpinned(URL)
    case removedDuplicateClaude(count: Int)
}

/// Opt-in Dock pinning for launchers. Only tiles that point at a
/// hats launcher are ever added or removed; the one exception is
/// `dedupeClaude`, which drops repeated pins of Claude.app and keeps the first.
public struct DockEditor: Sendable {
    let preferences: any DockPreferences

    #if canImport(AppKit)
    public init(preferences: any DockPreferences = SystemDockPreferences()) {
        self.preferences = preferences
    }
    #else
    public init(preferences: any DockPreferences) {
        self.preferences = preferences
    }
    #endif

    public func pinnedURLs() -> [URL] {
        preferences.persistentApps().compactMap(Self.url(of:))
    }

    public func pin(_ bundles: [URL], dedupeClaude claudeApp: URL? = nil, now: Date = Date()) throws(HatsError) -> [DockChange] {
        var apps = preferences.persistentApps()
        var changes: [DockChange] = []
        if let claudeApp {
            let matches = apps.indices.filter { Self.url(of: apps[$0]).map { Self.same($0, claudeApp) } ?? false }
            for index in matches.dropFirst().reversed() { apps.remove(at: index) }
            if matches.count > 1 { changes.append(.removedDuplicateClaude(count: matches.count - 1)) }
        }
        for bundle in bundles {
            let matches = apps.indices.filter { Self.url(of: apps[$0]).map { Self.same($0, bundle) } ?? false }
            if let valid = matches.first(where: { Self.isValid(apps[$0]) }) {
                for index in matches.reversed() where index != valid { apps.remove(at: index) }
                changes.append(.alreadyPinned(bundle))
                continue
            }
            for index in matches.reversed() { apps.remove(at: index) }
            apps.insert(Self.tile(for: bundle, now: now), at: insertionIndex(in: apps, claudeApp: claudeApp))
            changes.append(matches.isEmpty ? .pinned(bundle) : .repaired(bundle))
        }
        if changes.contains(where: { if case .alreadyPinned = $0 { false } else { true } }) {
            try preferences.setPersistentApps(apps)
            preferences.restartDock()
        }
        return changes
    }

    public func unpin(_ bundles: [URL]) throws(HatsError) -> [DockChange] {
        var apps = preferences.persistentApps()
        var changes: [DockChange] = []
        for bundle in bundles {
            let before = apps.count
            apps.removeAll { Self.url(of: $0).map { Self.same($0, bundle) } ?? false }
            if apps.count < before { changes.append(.unpinned(bundle)) }
        }
        if !changes.isEmpty {
            try preferences.setPersistentApps(apps)
            preferences.restartDock()
        }
        return changes
    }

    /// Launchers go right after the last launcher already pinned, else right
    /// after Claude.app, else at the end, so profiles stay grouped.
    private func insertionIndex(in apps: [[String: Any]], claudeApp: URL?) -> Int {
        if let last = apps.lastIndex(where: { Self.url(of: $0)?.lastPathComponent.hasPrefix("Claude (") == true }) {
            return last + 1
        }
        if let claudeApp, let index = apps.firstIndex(where: { Self.url(of: $0).map { Self.same($0, claudeApp) } ?? false }) {
            return index + 1
        }
        return apps.count
    }

    static func url(of tile: [String: Any]) -> URL? {
        guard let data = tile["tile-data"] as? [String: Any], let file = data["file-data"] as? [String: Any],
            let string = file["_CFURLString"] as? String
        else { return nil }
        return URL(string: string)
    }

    static func same(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.plainPath.lowercased() == rhs.standardizedFileURL.plainPath.lowercased()
    }

    /// The Dock silently skips tiles with a zero modification date, so such
    /// tiles are rewritten.
    static func isValid(_ tile: [String: Any]) -> Bool {
        guard tile["tile-type"] as? String == "file-tile", let data = tile["tile-data"] as? [String: Any],
            let file = data["file-data"] as? [String: Any], (file["_CFURLStringType"] as? Int) == 15
        else { return false }
        return ((data["file-mod-date"] as? NSNumber)?.int64Value ?? 0) != 0
    }

    static func tile(for bundle: URL, now: Date) -> [String: Any] {
        // HFS+ timestamps count seconds from 1904-01-01.
        let hfsNow = Int64(now.timeIntervalSince1970) + 2_082_844_800
        return [
            "tile-type": "file-tile",
            "tile-data": [
                "file-data": [
                    "_CFURLString": URL(filePath: bundle.plainPath, directoryHint: .isDirectory).absoluteString, "_CFURLStringType": 15,
                ],
                "file-label": bundle.deletingPathExtension().lastPathComponent,
                "file-type": 41,
                "file-mod-date": hfsNow,
                "parent-mod-date": hfsNow,
                "dock-extra": false,
                "is-beta": false,
            ] as [String: Any],
        ]
    }
}
