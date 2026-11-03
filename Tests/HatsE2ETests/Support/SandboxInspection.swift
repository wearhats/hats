import CryptoKit
import Foundation
import Testing

/// What a test seeds into the stand-ins and reads back from them. Plain files and
/// `JSONSerialization` only, so renaming something in HatsCore can't keep a test
/// passing.
extension E2ESandbox {
    var testDir: String { "\(root)/.test" }
    var eventLog: String { "\(testDir)/events.jsonl" }
    var dockPlist: String { "\(testDir)/dock.plist" }

    var eventLogText: String {
        (try? String(contentsOfFile: eventLog, encoding: .utf8)) ?? ""
    }

    func events(_ name: String? = nil) throws -> [[String: Any]] {
        let all = try eventLogText.split(separator: "\n").map { line in
            try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        return name.map { wanted in all.filter { $0["event"] as? String == wanted } } ?? all
    }

    func json(_ result: CommandResult) throws -> [[String: Any]] {
        try #require(try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [[String: Any]], "\(result)")
    }

    /// Runs `doctor --json` and also proves it changed nothing.
    func doctor(
        environment: [String: String] = [:], sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> (result: CommandResult, findings: [[String: Any]]) {
        let before = try snapshot()
        let result = try hats(["doctor", "--json"], environment: environment, sourceLocation: sourceLocation)
        #expect(try snapshot() == before, "doctor must not write. \(result)", sourceLocation: sourceLocation)
        return (result, try json(result))
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    func permissions(_ path: String) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int ?? 0
    }

    /// Each discarded item, as the name it had when it went to the stand-in Trash.
    func trashed() throws -> [String] {
        try events("trash").compactMap { $0["path"] as? String }
    }

    func profileDir(_ name: String) -> String { "\(hatsHome)/profiles/\(name)" }

    func launcher(_ label: String) -> String { "\(launcherDir)/Claude (\(label)).app" }

    /// Rewrites what `profile.json` records, as a hand edit could.
    func recordAdoptedDir(_ dir: String, inProfile name: String) throws {
        let file = "\(profileDir(name))/profile.json"
        var metadata = try #require(try JSONSerialization.jsonObject(with: Data(read(file).utf8)) as? [String: Any])
        metadata["externalCodeDir"] = dir
        try write(String(decoding: try JSONSerialization.data(withJSONObject: metadata), as: UTF8.self), to: file)
    }

    func metadata(ofProfile name: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(read("\(profileDir(name))/profile.json").utf8)) as? [String: Any])
    }

    func marker(in bundle: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(filePath: "\(bundle)/Contents/Resources/hats-launcher.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Claude Code's name for the Keychain item of a config dir.
    func keychainService(forConfigDir dir: String?) -> String {
        guard let dir else { return "Claude Code-credentials" }
        let hex = SHA256.hash(data: Data(dir.utf8)).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(hex.prefix(8))"
    }

    func seedKeychain(_ services: [String]) throws {
        try write(String(decoding: try JSONSerialization.data(withJSONObject: services), as: UTF8.self), to: "\(testDir)/keychain.json")
    }

    func seedURLHandler(_ path: String) throws {
        try write(path, to: "\(testDir)/claude-url-handler")
    }

    /// Never declares Claude's bundle ID or a `claude://` URL type: Launch Services
    /// can register any app it sees, and such a bundle could take the real handler.
    @discardableResult
    func makeApp(named name: String = "Claude", bundleID: String = "dev.wearhats.e2e.fake-claude") throws -> String {
        let app = "\(root)/apps/\(name).app"
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": "9.9.9", "CFBundleExecutable": name]
        try makeDirectory("\(app)/Contents/MacOS")
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: URL(filePath: "\(app)/Contents/Info.plist"))
        return app
    }

    var withClaudeApp: [String: String] {
        get throws { ["HATS_CLAUDE_APP": try makeApp()] }
    }

    /// `hats` on a directory of its own, for tests about what launchers call.
    func hatsOnPath(directory: String = "on-path") throws -> (path: String, environment: [String: String]) {
        let dir = "\(root)/\(directory)"
        try makeDirectory(dir)
        try FileManager.default.createSymbolicLink(atPath: "\(dir)/hats", withDestinationPath: try HatsBinary.path())
        return ("\(dir)/hats", ["PATH": "\(dir):/usr/bin:/bin"])
    }

    func dockTiles() throws -> [String] {
        guard exists(dockPlist) else { return [] }
        let data = try Data(contentsOf: URL(filePath: dockPlist))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let apps = try #require(plist["persistent-apps"] as? [[String: Any]])
        return apps.compactMap { (($0["tile-data"] as? [String: Any])?["file-data"] as? [String: Any])?["_CFURLString"] as? String }
    }

    func seedDock(urls: [String]) throws {
        let tiles: [[String: Any]] = urls.map { url in
            [
                "tile-type": "file-tile",
                "tile-data": ["file-data": ["_CFURLString": url, "_CFURLStringType": 15], "file-mod-date": 3_000_000_000],
            ]
        }
        try makeDirectory(testDir)
        try PropertyListSerialization.data(fromPropertyList: ["persistent-apps": tiles], format: .xml, options: 0)
            .write(to: URL(filePath: dockPlist))
    }
}

func hasFinding(_ findings: [[String: Any]], level: String, check: String? = nil, containing text: String) -> Bool {
    findings.contains {
        $0["level"] as? String == level && (check == nil || $0["check"] as? String == check)
            && ($0["message"] as? String)?.contains(text) == true
    }
}
