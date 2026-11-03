import AppKit
import Foundation
import Testing

/// What a stub app wrote about itself when it started.
struct StubReport {
    let pid: Int32
    let arguments: [String]
    let configDir: String?
}

struct WaitTimedOut: Error, CustomStringConvertible {
    let what: String
    var description: String { "timed out waiting for \(what)" }
}

/// Polls with a limit: these tests wait on the window server and Launch Services,
/// which have no handshake a test could block on.
func waitUntil<T>(_ what: String, timeoutSeconds: TimeInterval = 20, _ value: () throws -> T?) throws -> T {
    let deadline = Date.now.addingTimeInterval(timeoutSeconds)
    while Date.now < deadline {
        if let found = try value() { return found }
        usleep(50_000)
    }
    throw WaitTimedOut(what: what)
}

/// A real, regular `.app` around the fake. It declares only its own bundle ID and no
/// URL types: Launch Services can register any app it sees, and one that claimed
/// Claude's ID or `claude://` could take over for the real one.
final class StubApp {
    static let bundleID = "dev.wearhats.e2e.fake-claude"
    private static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    let path: String
    /// `stopEverything` reads reports out of the sandbox, so it has to outlive this.
    private let sandbox: E2ESandbox?
    private var directStarts: [Process] = []
    private var directory: String { (path as NSString).deletingLastPathComponent }
    var executable: String { "\(path)/Contents/MacOS/Claude" }

    init(at path: String, in sandbox: E2ESandbox? = nil) throws {
        self.path = path
        self.sandbox = sandbox
        let fm = FileManager.default
        try fm.createDirectory(atPath: "\(path)/Contents/MacOS", withIntermediateDirectories: true)
        try fm.copyItem(atPath: try FakeBinary.path(), toPath: executable)
        let info: [String: Any] = [
            "CFBundleIdentifier": Self.bundleID, "CFBundleExecutable": "Claude", "CFBundleName": "Fake Claude",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "9.9.9", "NSPrincipalClass": "NSApplication",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: URL(filePath: "\(path)/Contents/Info.plist"))
    }

    /// Started directly, which is how a duplicate on one data dir is made: `hats open`
    /// would focus the first instead.
    func startDirectly(arguments: [String], environment: [String: String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        directStarts.append(process)
        let pid = process.processIdentifier
        _ = try waitUntil("the stub \(pid) to report") { try reports().first { $0.pid == pid } }
        return pid
    }

    func reports() throws -> [StubReport] {
        try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasPrefix("report-") && $0.hasSuffix(".json") }
            .compactMap { name in
                let data = try Data(contentsOf: URL(filePath: "\(directory)/\(name)"))
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let pid = object["pid"] as? Int32 else {
                    return nil
                }
                return StubReport(pid: pid, arguments: object["arguments"] as? [String] ?? [], configDir: object["configDir"] as? String)
            }
    }

    /// Stops only what runs from this bundle, found by bundle path rather than by a
    /// reported PID, which may belong to another app by now. Then waits, so the
    /// profile no longer counts as running, and leaves no trace in Launch Services.
    func stopEverything() throws {
        for process in directStarts where process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        let standardizedPath = URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
        let launched = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).filter {
            $0.bundleURL?.standardizedFileURL.path(percentEncoded: false).hasPrefix(standardizedPath) == true
        }
        let launchedPIDs = launched.map(\.processIdentifier)
        launched.forEach { $0.forceTerminate() }
        _ = try waitUntil("the stub to stop") { launchedPIDs.allSatisfy { !isRunning($0) } ? true : nil }
        for name in try FileManager.default.contentsOfDirectory(atPath: directory) where name.hasPrefix("report-") {
            try FileManager.default.removeItem(atPath: "\(directory)/\(name)")
        }
        let unregister = try CommandRunner.run(executable: Self.lsregister, arguments: ["-u", path], environment: [:])
        #expect(unregister.exit == 0, "\(unregister)")
    }

    /// By signal 0: `NSRunningApplication` only updates from a run loop, which a test
    /// process doesn't spin, so it keeps saying a quit app is running.
    func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}
