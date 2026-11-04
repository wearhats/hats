import Foundation

/// `/Applications/Hats`, a symlink to the launcher dir. Finder's sidebar shows
/// `/Applications`, not the home folder's Applications, so without the link people
/// don't find the launchers. Made only on request. Every account on the Mac shares
/// `/Applications`, so hats only removes a link to this user's launcher dir or one
/// this account made.
public struct ApplicationsLink: Sendable {
    public static let name = "Hats"

    public enum State: Equatable, Sendable {
        /// The launcher dir is the Applications dir or inside it, and nothing of
        /// ours is at the link's path.
        case notNeeded
        case absent
        /// A link to this user's launcher dir, whoever made it. It dangles when
        /// that dir is missing.
        case ours(dangling: Bool)
        /// A link this account made that points elsewhere, such as one left from
        /// before `HATS_LAUNCHER_DIR` changed.
        case stale(destination: String)
        /// Another account's link (`destination`), or anything that isn't a link (`nil`).
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
    let accountID: uid_t

    public init(layout: Layout, applicationsDir: URL, accountID: uid_t) {
        self.applicationsDir = applicationsDir
        url = applicationsDir.appending(path: Self.name, directoryHint: .notDirectory)
        launcherDir = layout.launcherDir
        home = layout.home
        self.accountID = accountID
    }

    public func state() -> State {
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: url.plainPath) else {
            return launcherDirIsInApplicationsDir ? .notNeeded : .absent
        }
        guard (attributes[.type] as? FileAttributeType) == .typeSymbolicLink,
            let destination = try? fm.destinationOfSymbolicLink(atPath: url.plainPath)
        else {
            return launcherDirIsInApplicationsDir ? .notNeeded : .foreign(destination: nil)
        }
        let target =
            destination.hasPrefix("/")
            ? URL(filePath: destination, directoryHint: .isDirectory)
            : applicationsDir.appending(path: destination, directoryHint: .isDirectory)
        if target.canonicalPath == launcherDir.canonicalPath { return .ours(dangling: !fm.fileExists(atPath: url.plainPath)) }
        return ownerID(attributes) == accountID ? .stale(destination: destination) : .foreign(destination: destination)
    }

    public var canWriteApplicationsDir: Bool {
        FileManager.default.isWritableFile(atPath: applicationsDir.plainPath)
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
        // Before the check: the command printed for an admin must not make a
        // dangling link, and the launcher dir is hats' own.
        try createLauncherDir()
        guard canWriteApplicationsDir else { throw needsAdmin }
        do {
            try FileManager.default.createSymbolicLink(atPath: url.plainPath, withDestinationPath: launcherDir.plainPath)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw needsAdmin
        } catch {
            throw HatsError(.io, "cannot create \(url.plainPath): \(error.localizedDescription)")
        }
        return .created
    }

    /// Removes the link itself, never what it points at, and only when it is
    /// ours or this account's.
    @discardableResult
    public func unlink() throws(HatsError) -> UnlinkOutcome {
        let state = state()
        switch state {
        case .notNeeded, .absent:
            return .notLinked
        case .foreign:
            throw refusal(state)
        case .ours, .stale:
            break
        }
        do {
            try FileManager.default.removeItem(atPath: url.plainPath)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw HatsError(
                .environment, "only an admin account can remove \(url.plainPath)",
                hint: "from an admin account, run: sudo rm \(LauncherBuilder.shellQuote(url.plainPath))")
        } catch {
            throw HatsError(.io, "cannot remove \(url.plainPath): \(error.localizedDescription)")
        }
        return .removed
    }

    /// The command an admin can run instead of `link`. With `sudo` the link
    /// belongs to root rather than to the admin's account, whose own hats would
    /// otherwise take it for a stale link of its own and could remove it.
    public var manualCommand: String {
        "sudo ln -s \(LauncherBuilder.shellQuote(launcherDir.plainPath)) \(LauncherBuilder.shellQuote(url.plainPath))"
    }

    private func createLauncherDir() throws(HatsError) {
        try requireRunningAsHomeOwner()
        do {
            try FileManager.default.createDirectory(at: launcherDir, withIntermediateDirectories: true)
        } catch {
            throw HatsError(.io, "cannot create \(launcherDir.plainPath): \(error.localizedDescription)")
        }
    }

    /// `sudo` keeps HOME on macOS, so hats as root would make the launcher dir in
    /// this home owned by root, and the link would belong to root.
    private func requireRunningAsHomeOwner() throws(HatsError) {
        guard let homeAttributes = try? FileManager.default.attributesOfItem(atPath: home.canonicalPath),
            let owner = ownerID(homeAttributes), owner != accountID
        else { return }
        throw HatsError(
            .environment, "hats is running as another account than the owner of \(home.plainPath), as under sudo",
            hint: "run it without sudo: hats launcher link")
    }

    private func ownerID(_ attributes: [FileAttributeKey: Any]) -> uid_t? {
        (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
    }

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
                hint: "remove the old link with: hats launcher unlink, then run: hats launcher link")
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

    private var launcherDirIsInApplicationsDir: Bool {
        let launcherPath = launcherDir.canonicalPath
        let applicationsPath = applicationsDir.canonicalPath
        return launcherPath == applicationsPath
            || Layout.isStrictlyInside(URL(filePath: launcherPath), root: URL(filePath: applicationsPath))
    }
}
