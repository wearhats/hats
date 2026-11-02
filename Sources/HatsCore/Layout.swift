import Foundation

/// Every path hats reads or writes. Nothing else in the package builds paths
/// from scratch, which keeps the "never write outside these roots" rule auditable.
public struct Layout: Sendable, Equatable {
    public let home: URL
    public let hatsHome: URL
    public let launcherDir: URL
    public let defaultDesktopDir: URL
    public let defaultCodeDir: URL

    public init(environment: [String: String]) {
        let home = URL(filePath: environment["HOME"] ?? NSHomeDirectory(), directoryHint: .isDirectory)
        self.home = home
        hatsHome =
            Self.directory(environment["HATS_HOME"])
            ?? home.appending(path: "Library/Application Support/hats", directoryHint: .isDirectory)
        launcherDir =
            Self.directory(environment["HATS_LAUNCHER_DIR"])
            ?? home.appending(path: "Applications/Hats", directoryHint: .isDirectory)
        defaultDesktopDir = home.appending(path: "Library/Application Support/Claude", directoryHint: .isDirectory)
        // An inherited CLAUDE_CONFIG_DIR usually means "this shell is inside a
        // profile", so it must not redefine what `default` is.
        defaultCodeDir =
            Self.directory(environment["HATS_DEFAULT_CONFIG_DIR"])
            ?? home.appending(path: ".claude", directoryHint: .isDirectory)
    }

    public var profilesDir: URL { hatsHome.appending(path: "profiles", directoryHint: .isDirectory) }

    /// Written by `install.sh`, read by doctor; hats itself never writes it.
    public var installReceipt: URL { hatsHome.appending(path: "install.json", directoryHint: .notDirectory) }

    public var updateCheckState: URL { hatsHome.appending(path: "update-check.json", directoryHint: .notDirectory) }

    public func profileDir(_ name: ProfileName) -> URL {
        profilesDir.appending(path: name.rawValue, directoryHint: .isDirectory)
    }

    public func desktopDir(_ name: ProfileName) -> URL {
        name.isDefault ? defaultDesktopDir : profileDir(name).appending(path: "desktop", directoryHint: .isDirectory)
    }

    public func codeDir(_ name: ProfileName) -> URL {
        name.isDefault ? defaultCodeDir : profileDir(name).appending(path: "code", directoryHint: .isDirectory)
    }

    public func metadataFile(_ name: ProfileName) -> URL {
        profileDir(name).appending(path: "profile.json", directoryHint: .notDirectory)
    }

    /// Claude Code keeps its account and project state in `.claude.json`: in
    /// HOME for the stock install, inside the config dir when
    /// `CLAUDE_CONFIG_DIR` is set.
    public func codeStateFile(for profile: Profile) -> URL {
        (profile.isDefault ? home : profile.codeDir).appending(path: ".claude.json", directoryHint: .notDirectory)
    }

    public var desktopFolder: URL { home.appending(path: "Desktop", directoryHint: .isDirectory) }

    public func launcherBundle(label: String) -> URL {
        launcherDir.appending(path: "Claude (\(label)).app", directoryHint: .isDirectory)
    }

    /// Whether `url` lies strictly inside `root` once both are standardized.
    /// Guards every recursive delete.
    public static func isStrictlyInside(_ url: URL, root: URL) -> Bool {
        let child = url.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
        let parent = root.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
        return child.hasPrefix(parent + "/") && child.count > parent.count + 1
    }

    private static func directory(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        var result = self
        while result.count > 1, result.hasSuffix(suffix) { result.removeLast(suffix.count) }
        return result
    }
}

extension URL {
    /// The filesystem path without percent-encoding or a trailing slash. Used
    /// for every path hats hands to other programs (argv, env, Keychain hash).
    public var plainPath: String {
        path(percentEncoded: false).trimmingSuffix("/")
    }

    /// Canonical string form for equality checks between paths that came from
    /// different sources (argv, env, our own layout).
    var canonicalPath: String {
        standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false).trimmingSuffix("/")
    }
}
