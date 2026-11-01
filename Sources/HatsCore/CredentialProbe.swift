import Foundation

#if canImport(Security)
import CryptoKit
import Security
#endif

public enum CredentialState: String, Codable, Sendable {
    case present
    case absent
    case unknown
}

public protocol CredentialProbe: Sendable {
    func state(forConfigDir configDir: URL, isDefault: Bool) -> CredentialState
}

#if canImport(Security)
/// Checks whether Claude Code has a stored login for a config dir. Claude Code
/// names the Keychain item `Claude Code-credentials` when `CLAUDE_CONFIG_DIR`
/// is unset, else `Claude Code-credentials-<first 8 hex of sha256(dir)>`.
/// Only attributes are requested, never the secret, so no prompt appears.
public struct KeychainCredentialProbe: CredentialProbe {
    public init() {}

    public func state(forConfigDir configDir: URL, isDefault: Bool) -> CredentialState {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName(forConfigDir: configDir, isDefault: isDefault),
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        switch SecItemCopyMatching(query as CFDictionary, nil) {
        case errSecSuccess: return .present
        case errSecItemNotFound: return .absent
        default: return .unknown
        }
    }

    public static func serviceName(forConfigDir configDir: URL, isDefault: Bool) -> String {
        let base = "Claude Code-credentials"
        guard !isDefault else { return base }
        let digest = SHA256.hash(data: Data(configDir.plainPath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(base)-\(hex.prefix(8))"
    }
}
#endif
