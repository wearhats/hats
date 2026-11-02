import Foundation

#if canImport(CoreServices)
import CoreServices
#endif

/// Marker written into every bundle hats generates. hats only ever modifies or
/// deletes bundles that carry it.
public struct LauncherMarker: Codable, Equatable, Sendable {
    public static let fileName = "hats-launcher.json"
    public static let currentVersion = 1

    public let name: ProfileName
    public let launcherVersion: Int
    public let hatsPath: String
    /// Bundle paths of the copies placed with `copy(for:to:)`, kept only in
    /// the launcher itself. hats revisits exactly these instead of listing
    /// folders such as ~/Desktop, which can raise a privacy prompt. Absent in
    /// launchers written before copies were recorded.
    public var copies: [String]?
}

public struct LauncherStatus: Equatable, Sendable {
    public let bundle: URL
    public let marker: LauncherMarker

    public var isCurrent: Bool { marker.launcherVersion >= LauncherMarker.currentVersion }
    public var hatsExecutableExists: Bool { FileManager.default.isExecutableFile(atPath: marker.hatsPath) }
    public var copies: [URL] { (marker.copies ?? []).map { URL(filePath: $0, directoryHint: .isDirectory) } }
}

/// Tells Launch Services about a new or changed bundle, so Finder and the Dock
/// pick up its name and icon right away.
public struct AppRegistrar: Sendable {
    let register: @Sendable (URL) -> Void

    public init(_ register: @escaping @Sendable (URL) -> Void) {
        self.register = register
    }

    #if canImport(CoreServices)
    public static let launchServices = AppRegistrar { bundle in
        _ = LSRegisterURL(bundle as CFURL, true)
    }
    #else
    public static let launchServices = AppRegistrar { _ in }
    #endif
}

public struct LauncherBuilder: Sendable {
    public static let bundleIDPrefix = "dev.wearhats.launcher."

    let layout: Layout
    let registrar: AppRegistrar

    public init(layout: Layout, registrar: AppRegistrar) {
        self.layout = layout
        self.registrar = registrar
    }

    /// For callers that only look at launchers, and so never register anything.
    public static func reading(layout: Layout) -> LauncherBuilder {
        LauncherBuilder(layout: layout, registrar: AppRegistrar { _ in })
    }

    /// Writes (or rewrites) the profile's launcher and removes stale bundles
    /// for the same profile, such as after a label change. Recorded copies
    /// are refreshed too.
    @discardableResult
    public func build(for profile: Profile, hatsPath: String) throws(HatsError) -> URL {
        guard !profile.isDefault else { throw HatsError(.usage, "the default profile is launched by Claude.app itself") }
        let bundle = layout.launcherBundle(label: profile.label)
        var copies: [URL] = []
        do {
            if FileManager.default.fileExists(atPath: bundle.plainPath) {
                try requireOwned(bundle, by: profile.name)
            }
            for stale in try installed() where stale.marker.name == profile.name {
                copies += stale.copies
                try FileManager.default.removeItem(at: stale.bundle)
            }
            try writeBundle(at: bundle, for: profile, hatsPath: hatsPath)
        } catch let error as HatsError {
            throw error
        } catch {
            throw HatsError(.io, "cannot write launcher \(bundle.plainPath): \(error.localizedDescription)")
        }
        registrar.register(bundle)
        var refreshed: [URL] = []
        for old in copies {
            guard Self.marker(in: old)?.name == profile.name else { continue }
            let destination = old.deletingLastPathComponent().appending(path: bundle.lastPathComponent, directoryHint: .isDirectory)
            do {
                try FileManager.default.removeItem(at: old)
            } catch {
                throw HatsError(.io, "cannot replace the launcher copy \(old.plainPath): \(error.localizedDescription)")
            }
            refreshed.append(try place(bundle, at: destination, for: profile.name))
        }
        if !refreshed.isEmpty { try record(copies: refreshed, in: bundle) }
        return bundle
    }

    /// Removes the launcher and every copy of it that hats placed.
    public func remove(for name: ProfileName) throws(HatsError) {
        do {
            for launcher in try installed() where launcher.marker.name == name {
                for copy in launcher.copies where Self.marker(in: copy)?.name == name {
                    try FileManager.default.removeItem(at: copy)
                }
                try FileManager.default.removeItem(at: launcher.bundle)
            }
        } catch let error as HatsError {
            throw error
        } catch {
            throw HatsError(.io, "cannot remove launcher for '\(name)': \(error.localizedDescription)")
        }
    }

    /// Places a copy of the launcher in `directory` (usually the Desktop) for
    /// people who launch apps from there, and records it so later rebuilds
    /// and removals find it. APFS makes it a clone.
    @discardableResult
    public func copy(for name: ProfileName, to directory: URL) throws(HatsError) -> URL {
        guard let launcher = status(for: name) else {
            throw HatsError(.notFound, "no launcher for '\(name)'", hint: "create it with: hats launcher rebuild \(name)")
        }
        let destination = directory.appending(path: launcher.bundle.lastPathComponent, directoryHint: .isDirectory)
        do {
            for stale in installed(in: directory) where stale.marker.name == name {
                try FileManager.default.removeItem(at: stale.bundle)
            }
        } catch {
            throw HatsError(.io, "cannot replace the launcher copy in \(directory.plainPath): \(error.localizedDescription)")
        }
        let placed = try place(launcher.bundle, at: destination, for: name)
        let others = launcher.copies.filter { $0.canonicalPath != placed.canonicalPath && Self.marker(in: $0)?.name == name }
        try record(copies: others + [placed], in: launcher.bundle)
        return placed
    }

    public func installed() throws(HatsError) -> [LauncherStatus] {
        let path = layout.launcherDir.plainPath
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            throw HatsError(.io, "cannot read \(path): \(error.localizedDescription)")
        }
        return installed(in: layout.launcherDir)
    }

    /// hats bundles directly inside `directory`, identified by their marker.
    /// Only called for hats' own launcher dir or a folder the user named.
    public func installed(in directory: URL) -> [LauncherStatus] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.plainPath)) ?? []
        return entries.sorted().filter { $0.hasSuffix(".app") }.compactMap { entry in
            let bundle = directory.appending(path: entry, directoryHint: .isDirectory)
            return Self.marker(in: bundle).map { LauncherStatus(bundle: bundle, marker: $0) }
        }
    }

    public func status(for name: ProfileName) -> LauncherStatus? {
        (try? installed())?.first { $0.marker.name == name }
    }

    private func requireOwned(_ bundle: URL, by name: ProfileName) throws(HatsError) {
        guard let marker = Self.marker(in: bundle) else {
            throw HatsError(.conflict, "\(bundle.plainPath) exists and was not created by hats", hint: "move it away, then re-run")
        }
        guard marker.name == name else {
            throw HatsError(
                .conflict, "\(bundle.plainPath) is the launcher of profile '\(marker.name)'",
                hint: "give '\(name)' another label with: hats add \(name) --label <label>")
        }
    }

    private func place(_ launcher: URL, at destination: URL, for name: ProfileName) throws(HatsError) -> URL {
        do {
            if FileManager.default.fileExists(atPath: destination.plainPath) {
                try requireOwned(destination, by: name)
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: launcher, to: destination)
            if var marker = Self.marker(in: destination), marker.copies != nil {
                marker.copies = nil
                try writeMarker(marker, in: destination)
            }
        } catch let error as HatsError {
            throw error
        } catch {
            throw HatsError(.io, "cannot copy the launcher to \(destination.plainPath): \(error.localizedDescription)")
        }
        return destination
    }

    private func record(copies: [URL], in bundle: URL) throws(HatsError) {
        guard var marker = Self.marker(in: bundle) else { return }
        marker.copies = copies.isEmpty ? nil : copies.map(\.plainPath)
        do {
            try writeMarker(marker, in: bundle)
        } catch {
            throw HatsError(.io, "cannot update \(bundle.plainPath): \(error.localizedDescription)")
        }
    }

    private func writeMarker(_ marker: LauncherMarker, in bundle: URL) throws {
        try ProfileStore.encoder.encode(marker).write(to: Self.markerFile(in: bundle), options: .atomic)
    }

    private static func markerFile(in bundle: URL) -> URL {
        bundle.appending(path: "Contents/Resources/\(LauncherMarker.fileName)", directoryHint: .notDirectory)
    }

    static func marker(in bundle: URL) -> LauncherMarker? {
        (try? Data(contentsOf: markerFile(in: bundle))).flatMap { try? JSONDecoder().decode(LauncherMarker.self, from: $0) }
    }

    private func writeBundle(at bundle: URL, for profile: Profile, hatsPath: String) throws {
        let fm = FileManager.default
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        let macOS = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let displayName = "Claude (\(profile.label))"
        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": displayName,
            "CFBundleExecutable": "launch",
            "CFBundleIconFile": "AppIcon",
            "CFBundleIdentifier": Self.bundleIDPrefix + profile.name.rawValue,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": displayName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "\(LauncherMarker.currentVersion)",
            "CFBundleVersion": "\(LauncherMarker.currentVersion)",
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": true,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"), options: .atomic)

        let script = macOS.appending(path: "launch", directoryHint: .notDirectory)
        try Data(Self.launchScript(profile: profile.name, hatsPath: hatsPath, hatsHome: layout.hatsHome.plainPath).utf8).write(
            to: script, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.plainPath)

        // Without CoreGraphics (the Linux CI build) the bundle gets no icon, so
        // the rest of the bundle logic stays testable there.
        #if canImport(CoreGraphics)
        try IconRenderer.icns(glyph: IconRenderer.Glyph(profile), color: profile.color)
            .write(to: resources.appending(path: "AppIcon.icns"), options: .atomic)
        #endif

        try writeMarker(LauncherMarker(name: profile.name, launcherVersion: LauncherMarker.currentVersion, hatsPath: hatsPath), in: bundle)
    }

    /// Finder and the Dock start apps with launchd's environment, so the data
    /// root is pinned here rather than inherited.
    static func launchScript(profile: ProfileName, hatsPath: String, hatsHome: String) -> String {
        """
        #!/bin/sh
        # Generated by hats. Rebuild with: hats launcher rebuild
        export HATS_HOME=\(shellQuote(hatsHome))
        HATS=\(shellQuote(hatsPath))
        if [ ! -x "$HATS" ]; then
          /usr/bin/osascript -e 'display alert "hats is not installed" message "Reinstall hats, then run: hats launcher rebuild"' >/dev/null 2>&1
          exit 1
        fi
        exec "$HATS" open \(shellQuote(profile.rawValue))

        """
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
