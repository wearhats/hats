import Foundation

/// Desktop instances that share one data dir. Two Claude processes writing one
/// profile can corrupt it, and a Claude update can relaunch a
/// profile's window on the default data dir, which shows up here too.
public struct DuplicateGroup: Equatable, Sendable {
    public let dataDir: String
    public let keep: Instance
    public let extras: [Instance]
}

public enum DuplicateInstances {
    /// Keeps the oldest instance per data dir, so the one that has been open
    /// longest (and is most likely the one in use) survives.
    public static func groups(in instances: [Instance]) -> [DuplicateGroup] {
        let desktops = instances.filter { $0.kind == .desktop }
        return Dictionary(grouping: desktops) { URL(filePath: $0.dataDir).canonicalPath }
            .values
            .filter { $0.count > 1 }
            .map { group in
                let sorted = group.sorted { ($0.startedAt, $0.pid) < ($1.startedAt, $1.pid) }
                return DuplicateGroup(dataDir: sorted[0].dataDir, keep: sorted[0], extras: Array(sorted.dropFirst()))
            }
            .sorted { $0.dataDir < $1.dataDir }
    }
}

/// Where deleted profile data goes. The default is the user's Trash, so a
/// mistaken reset can be undone in Finder.
public struct Discarder: Sendable {
    let discard: @Sendable (URL) throws -> Void

    public init(_ discard: @escaping @Sendable (URL) throws -> Void) {
        self.discard = discard
    }

    public static let trash = Discarder { url in
        #if os(macOS)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        #else
        throw HatsError(.environment, "moving \(url.plainPath) to the Trash needs macOS")
        #endif
    }
}

extension ProfileStore {
    /// "Start fresh": moves the profile's Desktop data (and, with
    /// `includingCode`, its owned Claude Code dir) away and recreates them
    /// empty, so the next launch asks for a sign-in. Fixes a profile that
    /// opens on the wrong account. Callers make sure it isn't running.
    @discardableResult
    public func reset(_ name: ProfileName, includingCode: Bool, discarder: Discarder = .trash) throws(HatsError) -> [URL] {
        guard !name.isDefault else {
            throw HatsError(.usage, "the default profile is the stock Claude install; sign out inside Claude instead")
        }
        let profile = try profile(named: name)
        if includingCode, profile.codeDirIsExternal {
            throw HatsError(
                .usage, "'\(name)' uses the adopted Claude Code dir \(profile.codeDir.plainPath), which hats never deletes",
                hint: "to switch its account, run: hats run \(name), then /login")
        }
        let targets = includingCode ? [profile.desktopDir, profile.codeDir] : [profile.desktopDir]
        let fm = FileManager.default
        var discarded: [URL] = []
        for dir in targets {
            guard Layout.isStrictlyInside(dir, root: layout.profileDir(name)) else {
                throw HatsError(.io, "refusing to discard \(dir.plainPath): outside \(layout.profileDir(name).plainPath)")
            }
            do {
                if fm.fileExists(atPath: dir.plainPath) {
                    try discarder.discard(dir)
                    discarded.append(dir)
                }
                try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } catch {
                throw HatsError(.io, "cannot reset \(dir.plainPath): \(error.localizedDescription)")
            }
        }
        return discarded
    }
}

public enum DiskUsage {
    /// Bytes allocated on disk under `url`, without following symlinks.
    /// APFS clones count in full, so this over-reports cloned Cowork VMs.
    public static func allocatedSize(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Claude Code config dirs a user made by hand (`~/.claude-work`), which
/// `hats add --code-dir` can adopt without a new login.
public enum AdoptionCandidates {
    public static func find(layout: Layout, profiles: [Profile], instances: [Instance]) -> [URL] {
        let fm = FileManager.default
        var candidates = instances.filter { $0.kind != .desktop && $0.profile == nil }.map {
            URL(filePath: $0.dataDir, directoryHint: .isDirectory)
        }
        let entries = (try? fm.contentsOfDirectory(atPath: layout.home.plainPath)) ?? []
        for entry in entries.sorted() where entry.hasPrefix(".claude-") || entry.hasPrefix(".claude.") || entry.hasPrefix(".claude_") {
            let dir = layout.home.appending(path: entry, directoryHint: .isDirectory)
            let looksLikeConfigDir = [".claude.json", "settings.json", "projects", "sessions"].contains {
                fm.fileExists(atPath: dir.appending(path: $0).plainPath)
            }
            var isDirectory: ObjCBool = false
            if looksLikeConfigDir, fm.fileExists(atPath: dir.plainPath, isDirectory: &isDirectory), isDirectory.boolValue {
                candidates.append(dir)
            }
        }
        let taken = Set(profiles.map(\.codeDir.canonicalPath) + [layout.defaultCodeDir.canonicalPath])
        var seen = Set<String>()
        return candidates.filter { dir in
            let canonical = dir.canonicalPath
            return !taken.contains(canonical) && !Layout.isStrictlyInside(dir, root: layout.hatsHome) && seen.insert(canonical).inserted
        }
    }
}
