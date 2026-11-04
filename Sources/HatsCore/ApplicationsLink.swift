import Foundation

/// `/Applications/Hats`, a symlink to the launcher dir. Finder's sidebar shows
/// `/Applications`, not the home folder's Applications, so without the link people
/// don't find the launchers. Made only on request, and hats only ever removes a
/// link that points at this user's launcher dir.
public struct ApplicationsLink: Sendable {
    public static let name = "Hats"

    public enum State: Equatable, Sendable {
        /// The launcher dir is already inside the Applications dir.
        case notNeeded
        case absent
        /// A link to this user's launcher dir. It dangles when that dir is missing.
        case ours(dangling: Bool)
        /// A link into this user's home that isn't the launcher dir, such as one
        /// left from before `HATS_LAUNCHER_DIR` changed.
        case stale(destination: String)
        /// Another user's link (`destination`), or anything that isn't a link (`nil`).
        case foreign(destination: String?)
    }

    public enum LinkOutcome: Equatable, Sendable {
        case created, alreadyLinked, notNeeded
    }

    public enum UnlinkOutcome: Equatable, Sendable {
        case removed, notLinked
    }

    public let url: URL
    public let launcherDir: URL
    public let applicationsDir: URL
    let home: URL

    public init(layout: Layout, applicationsDir: URL) {
        self.applicationsDir = applicationsDir
        url = applicationsDir.appending(path: Self.name, directoryHint: .notDirectory)
        launcherDir = layout.launcherDir
        home = layout.home
    }

    public func state() -> State {
        if Self.isSameOrInside(launcherDir, applicationsDir) { return .notNeeded }
        let fm = FileManager.default
        guard let destination = try? fm.destinationOfSymbolicLink(atPath: url.plainPath) else {
            return (try? fm.attributesOfItem(atPath: url.plainPath)) == nil ? .absent : .foreign(destination: nil)
        }
        let target =
            destination.hasPrefix("/")
            ? URL(filePath: destination, directoryHint: .isDirectory)
            : applicationsDir.appending(path: destination, directoryHint: .isDirectory)
        if Self.isSame(target, launcherDir) { return .ours(dangling: !fm.fileExists(atPath: url.plainPath)) }
        if Self.isSameOrInside(target, home) { return .stale(destination: destination) }
        return .foreign(destination: destination)
    }

    /// Creates the link, and the launcher dir if it is missing so the link never
    /// dangles. Refuses, and changes nothing, when anything else is in the way.
    @discardableResult
    public func link() throws(HatsError) -> LinkOutcome {
        let state = state()
        switch state {
        case .notNeeded:
            return .notNeeded
        case .ours:
            try createLauncherDir()
            return .alreadyLinked
        case .stale, .foreign:
            throw refusal(state)
        case .absent:
            break
        }
        guard FileManager.default.isWritableFile(atPath: applicationsDir.plainPath) else { throw needsAdmin }
        try createLauncherDir()
        do {
            try FileManager.default.createSymbolicLink(atPath: url.plainPath, withDestinationPath: launcherDir.plainPath)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw needsAdmin
        } catch {
            throw HatsError(.io, "cannot create \(url.plainPath): \(error.localizedDescription)")
        }
        return .created
    }

    /// Removes the link itself, never what it points at, and only when it is ours.
    @discardableResult
    public func unlink() throws(HatsError) -> UnlinkOutcome {
        let state = state()
        switch state {
        case .notNeeded, .absent:
            return .notLinked
        case .stale, .foreign:
            throw refusal(state)
        case .ours:
            break
        }
        do {
            try FileManager.default.removeItem(atPath: url.plainPath)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw HatsError(
                .environment, "only an admin account can remove \(url.plainPath)",
                hint: "from an admin account, run: rm \(LauncherBuilder.shellQuote(url.plainPath))")
        } catch {
            throw HatsError(.io, "cannot remove \(url.plainPath): \(error.localizedDescription)")
        }
        return .removed
    }

    /// The command an admin can run instead of `link`.
    public var manualCommand: String {
        "ln -s \(LauncherBuilder.shellQuote(launcherDir.plainPath)) \(LauncherBuilder.shellQuote(url.plainPath))"
    }

    private func createLauncherDir() throws(HatsError) {
        do {
            try FileManager.default.createDirectory(at: launcherDir, withIntermediateDirectories: true)
        } catch {
            throw HatsError(.io, "cannot create \(launcherDir.plainPath): \(error.localizedDescription)")
        }
    }

    /// Not `sudo hats`: hats running as root would link root's launcher dir.
    private var needsAdmin: HatsError {
        HatsError(
            .environment, "only an admin account can add a link to \(applicationsDir.plainPath)",
            hint: "from an admin account, run: \(manualCommand)")
    }

    private func refusal(_ state: State) -> HatsError {
        switch state {
        case .stale(let destination):
            HatsError(
                .conflict, "\(url.plainPath) links to \(destination), not to your launcher dir \(launcherDir.plainPath)",
                hint: "remove the old link with: rm \(LauncherBuilder.shellQuote(url.plainPath)), then run: hats launcher link")
        case .foreign(let destination?):
            HatsError(
                .conflict, "\(url.plainPath) links to \(destination), not to your launcher dir, so hats leaves it alone",
                hint: "another account on this Mac may use it; open your launchers with: hats launcher reveal")
        default:
            HatsError(
                .conflict, "\(url.plainPath) exists and is not a link hats made, so hats leaves it alone",
                hint: "open your launchers with: hats launcher reveal")
        }
    }

    private static func isSame(_ lhs: URL, _ rhs: URL) -> Bool {
        canonical(lhs) == canonical(rhs)
    }

    private static func isSameOrInside(_ url: URL, _ root: URL) -> Bool {
        let path = canonical(url)
        let parent = canonical(root)
        return path == parent || path.hasPrefix(parent == "/" ? "/" : parent + "/")
    }

    /// `canonicalPath` of the deepest part that exists, plus the rest. A missing
    /// launcher dir is common, and `canonicalPath` resolves a missing path
    /// differently from an existing one (on macOS it strips `/private` only from
    /// the existing one), so comparing them directly would miss a match.
    static func canonical(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.plainPath), existing.plainPath != "/" {
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        return missing.reduce(existing.canonicalPath) { $0 == "/" ? "/" + $1 : $0 + "/" + $1 }
    }
}
