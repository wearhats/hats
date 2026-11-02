import Foundation

/// Which Claude account a profile's Desktop and Claude Code are signed in to.
/// Both files are plain JSON and are parsed whole in memory, because JSON
/// can't be read selectively. Desktop's `config.json` also holds its token
/// cache, so the parsed object never leaves the function that reads it: only
/// the presence of a token cache key and `lastKnownAccountUuid` are kept, and
/// from `.claude.json` only the account UUID, email and organization name.
public struct AccountInfo: Codable, Equatable, Sendable {
    public enum SignIn: String, Codable, Sendable {
        case signedIn = "signed-in"
        case signedOut = "signed-out"
        case neverOpened = "never-opened"
        case unknown
    }

    public var desktop: SignIn
    public var desktopAccountID: String?
    public var codeAccountID: String?
    public var codeEmail: String?
    public var codeOrganization: String?

    /// Desktop and Claude Code of one profile signed in to different accounts:
    /// Code-tab work would bill one account and terminal work another.
    public var isSplit: Bool {
        guard desktop == .signedIn, let desktopAccountID, let codeAccountID else { return false }
        return desktopAccountID != codeAccountID
    }

    /// The account to compare across profiles, preferring Desktop's.
    public var accountID: String? { desktop == .signedIn ? desktopAccountID ?? codeAccountID : codeAccountID }

    /// Part of the `--json` contract: a missing value prints as `null`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(desktop, forKey: .desktop)
        try container.encode(desktopAccountID, forKey: .desktopAccountID)
        try container.encode(codeAccountID, forKey: .codeAccountID)
        try container.encode(codeEmail, forKey: .codeEmail)
        try container.encode(codeOrganization, forKey: .codeOrganization)
    }
}

public struct AccountProbe: Sendable {
    let layout: Layout

    public init(layout: Layout) {
        self.layout = layout
    }

    public func info(for profile: Profile) -> AccountInfo {
        var info = AccountInfo(desktop: .neverOpened)
        let desktopConfig = profile.desktopDir.appending(path: "config.json", directoryHint: .notDirectory)
        if FileManager.default.fileExists(atPath: desktopConfig.plainPath) {
            (info.desktop, info.desktopAccountID) = Self.desktopSignIn(at: desktopConfig)
        }
        (info.codeAccountID, info.codeEmail, info.codeOrganization) = Self.codeAccount(at: layout.codeStateFile(for: profile))
        return info
    }

    private static func desktopSignIn(at config: URL) -> (AccountInfo.SignIn, accountID: String?) {
        guard let object = jsonObject(at: config) else { return (.unknown, nil) }
        let hasToken = object.keys.contains { $0.hasPrefix("oauth:tokenCache") }
        return (hasToken ? .signedIn : .signedOut, object["lastKnownAccountUuid"] as? String)
    }

    private static func codeAccount(at stateFile: URL) -> (id: String?, email: String?, organization: String?) {
        guard let account = jsonObject(at: stateFile)?["oauthAccount"] as? [String: Any] else { return (nil, nil, nil) }
        return (account["accountUuid"] as? String, account["emailAddress"] as? String, account["organizationName"] as? String)
    }

    private static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
