import Foundation

/// How the running hats binary was installed, so doctor can name the command
/// that upgrades it. hats never upgrades itself.
public enum InstallChannel: Equatable, Sendable {
    case homebrew
    case script(directory: String)
    /// A source build, a copied binary, or a script install whose receipt is gone.
    case unknown

    public static let installScriptURL = "https://wearhats.dev/install.sh"

    public static func detect(executable: URL, layout: Layout) -> InstallChannel {
        let path = executable.canonicalPath
        if path.contains("/Cellar/hats/") { return .homebrew }
        if let receipt = InstallReceipt.read(layout: layout),
            URL(filePath: receipt.path).canonicalPath == path
        {
            return .script(directory: URL(filePath: path).deletingLastPathComponent().plainPath)
        }
        return .unknown
    }

    public func upgradeCommand(home: String) -> String? {
        switch self {
        case .homebrew:
            return "brew upgrade hats"
        case .script(let directory):
            let defaultDirectory = URL(filePath: home).appending(path: ".local/bin").plainPath
            let base = "curl -fsSL \(Self.installScriptURL) | sh"
            return directory == defaultDirectory ? base : "\(base) -s -- --dir \(LauncherBuilder.shellQuote(directory))"
        case .unknown:
            return nil
        }
    }

    var installedWith: String {
        switch self {
        case .homebrew: "installed with Homebrew"
        case .script: "installed by the install script"
        case .unknown: "not installed with Homebrew or the install script"
        }
    }
}

/// Written by `install.sh` to `$HATS_HOME/install.json`. Only `path` is
/// needed; the other fields are for people reading the file.
struct InstallReceipt: Decodable {
    let path: String

    static func read(layout: Layout) -> InstallReceipt? {
        guard let data = try? Data(contentsOf: layout.installReceipt) else { return nil }
        return try? JSONDecoder().decode(InstallReceipt.self, from: data)
    }
}

/// The running hats and the hats that launchers should call, for doctor.
public struct HatsInstall: Sendable {
    public let version: String
    public let executable: URL
    public let launcherTarget: String

    public init(version: String, executable: URL, launcherTarget: String) {
        self.version = version
        self.executable = executable
        self.launcherTarget = launcherTarget
    }
}
