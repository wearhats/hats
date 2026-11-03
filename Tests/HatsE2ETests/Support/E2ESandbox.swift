import Foundation
import Testing

extension Tag {
    @Tag static var e2e: Self
}

/// A throwaway root per test, with an explicit environment that is never
/// inherited. Unit tests' `Sandbox` is deliberately not reused: that one lives
/// in a target that imports HatsCore.
final class E2ESandbox {
    let root: String
    let home: String
    let hatsHome: String
    let launcherDir: String
    let defaultConfigDir: String
    /// Planted where a token would be. No output may ever contain it.
    let sentinel = "hats-e2e-sentinel-\(UUID().uuidString)"
    /// Held here so a fake lives as long as the sandbox it was started in, however
    /// early the optimizer would release a test's own reference.
    var fakes: [FakeProcess] = []

    init(hatsHomeName: String = "hats-home") throws {
        let parent = canonicalPath(FileManager.default.temporaryDirectory.path(percentEncoded: false))
        root = "\(parent)/hats-e2e-\(UUID().uuidString)"
        home = "\(root)/home"
        hatsHome = "\(root)/\(hatsHomeName)"
        launcherDir = "\(root)/launchers"
        defaultConfigDir = "\(home)/.claude"
        try makeDirectory(home)
        try makeDirectory("\(root)/tmp")
        try write("", to: "\(root)/.hats-test-sandbox")
        try write(#"{"oauthAccount":{"accessToken":"\#(sentinel)"}}"#, to: "\(home)/.claude.json")
        try write(#"{"oauth:tokenCache":"\#(sentinel)"}"#, to: "\(home)/Library/Application Support/Claude/config.json")
    }

    deinit {
        fakes.forEach { $0.stop() }
        try? FileManager.default.removeItem(atPath: root)
    }

    var environment: [String: String] {
        [
            "HATS_TEST_SANDBOX": root,
            "HOME": home,
            "HATS_HOME": hatsHome,
            "HATS_LAUNCHER_DIR": launcherDir,
            "HATS_DEFAULT_CONFIG_DIR": defaultConfigDir,
            "NO_COLOR": "1",
            "TZ": "UTC",
            "LANG": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin",
            "TMPDIR": "\(root)/tmp",
        ]
    }

    /// Runs the binary under test, and fails the test if a planted secret reaches its output.
    func hats(
        _ arguments: [String],
        environment overrides: [String: String] = [:],
        removing removed: Set<String> = [],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> CommandResult {
        let result = try guarded(try HatsBinary.path(), arguments, environment: overrides, removing: removed)
        if leaksSentinel(result) || eventLogText.contains(sentinel) {
            Issue.record("A planted secret reached the output.\n\(result)", sourceLocation: sourceLocation)
        }
        return result
    }

    func guarded(
        _ executable: String,
        _ arguments: [String],
        environment overrides: [String: String] = [:],
        removing removed: Set<String> = [],
        protectedHome: String = SeatbeltGuard.realHome
    ) throws -> CommandResult {
        let wrapped = try SeatbeltGuard.wrap(
            executable: executable, arguments: arguments, sandboxRoot: root, protectedHome: protectedHome)
        return try CommandRunner.run(
            executable: wrapped.executable,
            arguments: wrapped.arguments,
            environment: environment.merging(overrides) { _, override in override }.filter { !removed.contains($0.key) },
            workingDirectory: URL(filePath: root, directoryHint: .isDirectory)
        )
    }

    func leaksSentinel(_ result: CommandResult) -> Bool {
        result.stdout.contains(sentinel) || result.stderr.contains(sentinel)
    }

    /// Written by hand from the documented schema rather than by `hats add`, so
    /// these tests double as a check that hats reads a profile written earlier.
    @discardableResult
    func addProfile(
        _ name: String, label: String? = nil, adopting adoptedDir: String? = nil, shortcut: String? = nil, schemaVersion: Int = 1
    ) throws -> String {
        let dir = "\(hatsHome)/profiles/\(name)"
        try write(#"{"oauth:tokenCache":"\#(sentinel)"}"#, to: "\(dir)/desktop/config.json")
        try write(#"{"accessToken":"\#(sentinel)"}"#, to: "\(adoptedDir ?? "\(dir)/code")/.claude.json")
        var metadata: [String: Any] = [
            "schemaVersion": schemaVersion,
            "label": label ?? name.prefix(1).uppercased() + name.dropFirst(),
            "color": "#1565C0",
            "icon": "letter",
            "createdAt": "2026-01-01T00:00:00Z",
        ]
        if let adoptedDir { metadata["externalCodeDir"] = adoptedDir }
        if let shortcut { metadata["shortcut"] = shortcut }
        let json = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        try write(String(decoding: json, as: UTF8.self), to: "\(dir)/profile.json")
        return adoptedDir ?? "\(dir)/code"
    }

    func makeDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func write(_ contents: String, to path: String) throws {
        try makeDirectory((path as NSString).deletingLastPathComponent)
        try Data(contents.utf8).write(to: URL(filePath: path))
    }

    /// Every entry under the root with its permissions and bytes. Modification
    /// times are left out on purpose: reading a file mustn't count as a change,
    /// and an identical rewrite doesn't matter to anyone.
    func snapshot() throws -> [String: String] {
        let fm = FileManager.default
        var entries: [String: String] = [:]
        for relative in try fm.subpathsOfDirectory(atPath: root) {
            let path = "\(root)/\(relative)"
            let attributes = try fm.attributesOfItem(atPath: path)
            let permissions = attributes[.posixPermissions] as? Int ?? 0
            let content: String =
                switch attributes[.type] as? FileAttributeType {
                case .typeRegular?: try Data(contentsOf: URL(filePath: path)).base64EncodedString()
                case .typeSymbolicLink?: try fm.destinationOfSymbolicLink(atPath: path)
                default: ""
                }
            entries[relative] = "\(String(permissions, radix: 8)) \(content)"
        }
        return entries
    }
}
