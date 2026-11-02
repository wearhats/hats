import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `MAJOR.MINOR.PATCH`, with an optional leading `v`. Pre-releases and
/// anything else are nil, so dev builds never take part in update checks.
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]

    public init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in part.allSatisfy(\.isASCII) ? Int(part) : nil }
        guard parts.count == 3, numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        components = numbers
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

/// Where the latest release's version comes from. The only network access in hats.
public protocol ReleaseFeed: Sendable {
    func latestVersion() async throws -> String
}

/// GitHub's "latest release" API: one unauthenticated GET that sends nothing
/// but the User-Agent, and keeps nothing from the reply but `tag_name`.
public struct GitHubReleaseFeed: ReleaseFeed {
    public static let endpoint = URL(string: "https://api.github.com/repos/wearhats/hats/releases/latest")!

    let userAgent: String

    public init(currentVersion: String) {
        userAgent = "hats/\(currentVersion)"
    }

    public func latestVersion() async throws -> String {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return Self.version(fromTag: try JSONDecoder().decode(Release.self, from: data).tagName)
    }

    /// 0.1.0 was tagged `hats-v0.1.0`; later releases are tagged `v<version>`.
    static func version(fromTag tag: String) -> String {
        tag.hasPrefix("hats-") ? String(tag.dropFirst("hats-".count)) : tag
    }

    private struct Release: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }
}

public struct UpdateNotice: Equatable, Sendable {
    public let current: SemanticVersion
    public let latest: SemanticVersion
    public let upgradeCommand: String?

    public var message: String { "A new release of hats is available: \(current) → \(latest)" }
    public var releaseURL: String { "https://github.com/wearhats/hats/releases/latest" }
}

/// Warns about a newer release; never downloads or installs it. Asks the
/// feed at most once per `interval`, failed attempts included, so an offline
/// Mac doesn't retry on every command.
public struct UpdateCheck: Sendable {
    public static let interval: TimeInterval = 24 * 60 * 60
    public static let optOutVariable = "HATS_NO_UPDATE_CHECK"

    let layout: Layout
    let feed: any ReleaseFeed
    let now: @Sendable () -> Date

    public init(layout: Layout, feed: any ReleaseFeed, now: @escaping @Sendable () -> Date = Date.init) {
        self.layout = layout
        self.feed = feed
        self.now = now
    }

    /// Off for dev builds, scripts, launchers and CI: only a person at a
    /// terminal sees the notice, so nobody else should cause the request.
    public static func isEnabled(currentVersion: String, environment: [String: String], stderrIsTerminal: Bool) -> Bool {
        guard stderrIsTerminal, SemanticVersion(currentVersion) != nil else { return false }
        return [optOutVariable, "CI"].allSatisfy { environment[$0]?.isEmpty ?? true }
    }

    public func isDue() -> Bool {
        guard let state = readState() else { return true }
        let elapsed = now().timeIntervalSince(state.checkedAt)
        return elapsed < 0 || elapsed >= Self.interval
    }

    /// Records the attempt before asking, so a command that exits before a
    /// slow reply arrives doesn't make the next command ask again.
    public func refresh() async {
        let previous = readState()?.latestVersion
        let started = now()
        writeState(State(checkedAt: started, latestVersion: previous))
        guard let latest = try? await feed.latestVersion() else { return }
        writeState(State(checkedAt: started, latestVersion: latest))
    }

    public func notice(currentVersion: String, channel: InstallChannel, home: String) -> UpdateNotice? {
        guard let current = SemanticVersion(currentVersion),
            let latest = readState()?.latestVersion.flatMap(SemanticVersion.init),
            latest > current
        else { return nil }
        return UpdateNotice(current: current, latest: latest, upgradeCommand: channel.upgradeCommand(home: home))
    }

    private struct State: Codable {
        let checkedAt: Date
        let latestVersion: String?
    }

    private func readState() -> State? {
        guard let data = try? Data(contentsOf: layout.updateCheckState) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(State.self, from: data)
    }

    private func writeState(_ state: State) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(at: layout.hatsHome, withIntermediateDirectories: true)
        try? data.write(to: layout.updateCheckState, options: .atomic)
    }
}
