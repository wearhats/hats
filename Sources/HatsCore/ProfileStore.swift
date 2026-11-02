import Foundation

public struct ProfileInventory: Sendable {
    public let profiles: [Profile]
    public let unreadableProfiles: [UnreadableProfile]
}

public struct UnreadableProfile: Sendable {
    public let name: ProfileName
    public let error: HatsError
}

public enum ShortcutChange: Sendable {
    case set(ProfileName)
    case clear
}

public struct ProfileStore: Sendable {
    public let layout: Layout

    public init(layout: Layout) {
        self.layout = layout
    }

    public var defaultProfile: Profile {
        Profile(
            name: .default,
            label: "Default",
            color: "#616161",
            desktopDir: layout.defaultDesktopDir,
            codeDir: layout.defaultCodeDir,
            createdAt: nil,
            codeDirIsExternal: true
        )
    }

    /// `default` first, then the readable managed profiles by name. Profiles
    /// that cannot be read are left out; `inventory()` reports them.
    public func list() throws(HatsError) -> [Profile] {
        try inventory().profiles
    }

    /// Each managed profile is read on its own, so one unreadable profile.json
    /// never hides its siblings.
    public func inventory() throws(HatsError) -> ProfileInventory {
        let fm = FileManager.default
        guard fm.fileExists(atPath: layout.profilesDir.plainPath) else {
            return ProfileInventory(profiles: [defaultProfile], unreadableProfiles: [])
        }
        let entries: [String]
        do {
            entries = try fm.contentsOfDirectory(atPath: layout.profilesDir.plainPath)
        } catch {
            throw HatsError(.io, "cannot read \(layout.profilesDir.plainPath): \(error.localizedDescription)")
        }
        let names =
            entries
            .compactMap { try? ProfileName($0) }
            .filter { !$0.isDefault && fm.fileExists(atPath: layout.metadataFile($0).plainPath) }
            .sorted()
        var managed: [Profile] = []
        var unreadable: [UnreadableProfile] = []
        for name in names {
            do {
                managed.append(try load(name))
            } catch {
                unreadable.append(UnreadableProfile(name: name, error: error))
            }
        }
        return ProfileInventory(profiles: [defaultProfile] + managed, unreadableProfiles: unreadable)
    }

    public func profile(named name: ProfileName) throws(HatsError) -> Profile {
        if name.isDefault { return defaultProfile }
        guard exists(name) else {
            throw HatsError(.notFound, "no profile named '\(name)'", hint: "create it with: hats add \(name)")
        }
        return try load(name)
    }

    /// What a person typed: a profile's name or, failing that, its shortcut.
    public func profile(matching raw: String) throws(HatsError) -> Profile {
        let name = try ProfileName(raw)
        if exists(name) { return try profile(named: name) }
        let known = try inventory()
        // An unreadable profile may claim this shortcut too, so a single readable
        // owner doesn't prove the shortcut is unambiguous.
        if let broken = known.unreadableProfiles.first {
            throw cannotCheck("cannot check whether '\(name)' is a shortcut", because: broken)
        }
        let owners = known.profiles.filter { $0.shortcut == name }
        // `add` refuses this, but a hand edit or a profile put back from the Trash
        // gets here. Picking one could run a command on the wrong account.
        guard owners.count <= 1 else {
            let names = owners.map { "'\($0.name)'" }.joined(separator: ", ")
            throw HatsError(.conflict, "the shortcut '\(name)' is claimed by \(names)", hint: "use the full name")
        }
        if let owner = owners.first { return owner }
        return try profile(named: name)
    }

    /// For commands that discard data, so doing that always means typing the name.
    public func profile(fullName raw: String) throws(HatsError) -> Profile {
        let name = try ProfileName(raw)
        if exists(name) { return try profile(named: name) }
        let owner = try profile(matching: raw)
        throw HatsError(
            .usage, "'\(name)' is the shortcut of profile '\(owner.name)'",
            hint: "this command takes the full name: \(owner.name)")
    }

    /// What `ps --profile` filters by. Nothing runs under a name no profile has,
    /// so that lists nothing. Any other failure leaves the owner unknown, where
    /// listing nothing would falsely report that the profile is idle.
    public func instanceFilter(matching raw: String) throws(HatsError) -> ProfileName {
        do {
            return try profile(matching: raw).name
        } catch {
            guard error.kind == .notFound else { throw error }
            return try ProfileName(raw)
        }
    }

    public func exists(_ name: ProfileName) -> Bool {
        name.isDefault || FileManager.default.fileExists(atPath: layout.metadataFile(name).plainPath)
    }

    /// Idempotent: an existing profile keeps its data, and only the given
    /// label, colour, icon, shortcut or adopted code dir is updated.
    @discardableResult
    public func create(
        _ name: ProfileName,
        label: String? = nil,
        color: ProfileColor? = nil,
        adoptingCodeDir externalCodeDir: URL? = nil,
        icon: LauncherIcon? = nil,
        shortcut: ShortcutChange? = nil,
        now: Date = Date()
    ) throws(HatsError) -> (profile: Profile, created: Bool) {
        guard !name.isDefault else {
            throw HatsError(.usage, "'default' is the stock Claude install and is managed by Claude itself")
        }
        if let label { try Self.validate(label: label) }
        if let externalCodeDir { try validate(adoptable: externalCodeDir) }
        let created = !exists(name)
        var metadata =
            created
            ? ProfileMetadata(label: name.defaultLabel, color: .automatic(for: name), createdAt: now, icon: .automatic(for: name))
            : try readMetadata(name)
        if let label { metadata.label = label }
        if let icon { metadata.icon = icon }
        if let color { metadata.color = color }
        if let externalCodeDir { metadata.externalCodeDir = externalCodeDir.plainPath }
        switch shortcut {
        case .set(let value)?: metadata.shortcut = value
        case .clear?: metadata.shortcut = nil
        case nil: break
        }
        let others = try readableSiblings(
            of: name, check: Self.uniquenessCheck(label: metadata.label, adopting: externalCodeDir, shortcut: shortcut))
        if let externalCodeDir { try requireUnused(codeDir: externalCodeDir, among: others) }
        try requireUnique(label: metadata.label, for: name, among: others)
        // A re-run checks only what it claims, so changing a colour can't fail on
        // a name or shortcut that was already there.
        if created { try requireFree(name: name, among: others) }
        if case .set(let value)? = shortcut { try requireFree(shortcut: value, of: name, among: others) }

        do {
            var ownedDirs = [layout.desktopDir(name)]
            if metadata.externalCodeDir == nil { ownedDirs.append(layout.codeDir(name)) }
            for dir in ownedDirs {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            try write(metadata, for: name)
        } catch let error as HatsError {
            throw error
        } catch {
            throw HatsError(.io, "cannot create profile '\(name)': \(error.localizedDescription)")
        }
        return (try load(name), created)
    }

    /// Moves the profile's own directory to the Trash (or `discarder`). An
    /// adopted code dir lives outside it and is left alone. A running profile
    /// is never purged, whatever the caller asks. Callers confirm with the
    /// user first.
    public func purge(_ name: ProfileName, processes: any ProcessTable, discarder: Discarder = .trash) throws(HatsError) {
        guard !name.isDefault else { throw HatsError(.usage, "refusing to delete the default Claude install") }
        let dir = layout.profileDir(name)
        guard Layout.isStrictlyInside(dir, root: layout.profilesDir) else {
            throw HatsError(.io, "refusing to delete \(dir.plainPath): outside \(layout.profilesDir.plainPath)")
        }
        guard exists(name) else { throw HatsError(.notFound, "no profile named '\(name)'") }
        // Running instances can only be matched to a readable profile, so an
        // unreadable one must not be purged on the assumption that it is idle.
        _ = try load(name)
        let running = InstanceScanner(profiles: try list(), processes: processes).scan().instances.filter { $0.profile == name }
        guard running.isEmpty else {
            throw HatsError(
                .conflict,
                "profile '\(name)' is running (pids \(running.map { String($0.pid) }.joined(separator: ", "))), so its data stays",
                hint: "quit it, then re-run")
        }
        do {
            try discarder.discard(dir)
        } catch {
            throw HatsError(.io, "cannot move \(dir.plainPath) to the Trash: \(error.localizedDescription)")
        }
    }

    /// The other managed profiles. Every uniqueness check takes this list, so
    /// none can run against a partial one. Refusing is the only safe answer while
    /// a profile cannot be read: its label, adopted dir and shortcut are unknown,
    /// so it may already own what is claimed.
    private func readableSiblings(of name: ProfileName, check: String) throws(HatsError) -> [Profile] {
        let known = try inventory()
        if let broken = known.unreadableProfiles.first(where: { $0.name != name }) {
            throw cannotCheck(check, because: broken)
        }
        return known.profiles.filter { !$0.isDefault && $0.name != name }
    }

    /// Names what the person asked for, not whichever check happens to run first.
    private static func uniquenessCheck(label: String, adopting dir: URL?, shortcut: ShortcutChange?) -> String {
        if let dir { return "cannot check whether \(dir.plainPath) is used by another profile" }
        if case .set(let value)? = shortcut { return "cannot check that the shortcut '\(value)' is unused" }
        return "cannot check that the label '\(label)' is unused"
    }

    private func requireUnused(codeDir dir: URL, among others: [Profile]) throws(HatsError) {
        let canonical = dir.canonicalPath
        if let owner = others.first(where: { $0.codeDir.canonicalPath == canonical }) {
            throw HatsError(.conflict, "\(dir.plainPath) is already used by profile '\(owner.name)'")
        }
    }

    /// Launchers are named after labels, and APFS compares names without case.
    private func requireUnique(label: String, for name: ProfileName, among others: [Profile]) throws(HatsError) {
        if let owner = others.first(where: { $0.label.compare(label, options: .caseInsensitive) == .orderedSame }) {
            throw HatsError(
                .conflict, "the label '\(label)' is already used by profile '\(owner.name)'",
                hint: "pick another with: hats add \(name) --label <label>")
        }
    }

    /// Names and shortcuts share one lookup, and a name wins it. Without this,
    /// a later `hats add w` would silently move `hats run w` to another account.
    private func requireFree(name: ProfileName, among others: [Profile]) throws(HatsError) {
        if let owner = others.first(where: { $0.shortcut == name }) {
            let add = "hats add \(owner.name)"
            throw HatsError(
                .conflict, "'\(name)' is the shortcut of profile '\(owner.name)'",
                hint: "to change it, run: \(add); for a new profile, pick another name or run: \(add) --no-shortcut")
        }
    }

    private func requireFree(shortcut: ProfileName, of name: ProfileName, among others: [Profile]) throws(HatsError) {
        guard !shortcut.isDefault else {
            throw HatsError(.usage, "'default' can't be a shortcut: it always means the stock Claude install")
        }
        guard shortcut != name else {
            throw HatsError(.usage, "the shortcut '\(shortcut)' is the profile's own name", hint: "pick a different one")
        }
        if let owner = others.first(where: { $0.name == shortcut }) {
            throw HatsError(.conflict, "the shortcut '\(shortcut)' is the name of profile '\(owner.name)'")
        }
        if let owner = others.first(where: { $0.shortcut == shortcut }) {
            throw HatsError(
                .conflict, "the shortcut '\(shortcut)' is already used by profile '\(owner.name)'",
                hint: "free it with: hats add \(owner.name) --no-shortcut")
        }
    }

    private func cannotCheck(_ check: String, because broken: UnreadableProfile) -> HatsError {
        let file = layout.metadataFile(broken.name).plainPath
        let otherFix = broken.error.hint.map { "\($0), or " } ?? ""
        return HatsError(
            broken.error.kind,
            "\(check): profile '\(broken.name)' cannot be read (\(broken.error.message))",
            hint: "\(otherFix)fix or remove \(file) (`hats doctor` shows it), then try again")
    }

    private func validate(adoptable dir: URL) throws(HatsError) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.plainPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HatsError(.notFound, "\(dir.plainPath) is not an existing directory")
        }
        let canonical = dir.canonicalPath
        guard canonical != layout.defaultCodeDir.canonicalPath else {
            throw HatsError(.usage, "\(dir.plainPath) is the default profile's config dir")
        }
        guard !Layout.isStrictlyInside(dir, root: layout.hatsHome), canonical != layout.hatsHome.canonicalPath else {
            throw HatsError(.usage, "\(dir.plainPath) is inside hats' own data directory")
        }
    }

    static func validate(label: String) throws(HatsError) {
        let forbidden = CharacterSet(charactersIn: "/:\0\n\r")
        guard !label.isEmpty, label.count <= 40, label.rangeOfCharacter(from: forbidden) == nil else {
            throw HatsError(.usage, "invalid label '\(label)'", hint: "use up to 40 characters without '/', ':' or newlines")
        }
    }

    private func load(_ name: ProfileName) throws(HatsError) -> Profile {
        let metadata = try readMetadata(name)
        return Profile(
            name: name,
            label: metadata.label,
            color: metadata.color,
            desktopDir: layout.desktopDir(name),
            codeDir: metadata.externalCodeDir.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? layout.codeDir(name),
            createdAt: metadata.createdAt,
            codeDirIsExternal: metadata.externalCodeDir != nil,
            icon: metadata.icon ?? .letter,
            shortcut: metadata.shortcut
        )
    }

    private func readMetadata(_ name: ProfileName) throws(HatsError) -> ProfileMetadata {
        let file = layout.metadataFile(name)
        let metadata: ProfileMetadata
        do {
            metadata = try Self.decoder.decode(ProfileMetadata.self, from: Data(contentsOf: file))
        } catch {
            throw HatsError(.io, "cannot read \(file.plainPath): \(error.localizedDescription)")
        }
        guard metadata.schemaVersion <= ProfileMetadata.currentSchemaVersion else {
            throw HatsError(
                .environment,
                "profile '\(name)' was written by a newer hats (schema \(metadata.schemaVersion))",
                hint: "upgrade hats"
            )
        }
        return metadata
    }

    private func write(_ metadata: ProfileMetadata, for name: ProfileName) throws {
        try Self.encoder.encode(metadata).write(to: layout.metadataFile(name), options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
