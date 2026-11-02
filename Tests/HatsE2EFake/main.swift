import AppKit
import CoreServices
@preconcurrency import Darwin
import Foundation

// A stand-in for a running Claude, for the end-to-end tests. hats tells processes
// apart by kernel name, executable path and argv, so this has to be a compiled
// binary run from a copy with the right name: a script reports `sh` to the kernel.
//
// Configured through the environment, because argv is part of what hats inspects:
//   HATS_FAKE_SESSION     JSON fields for <config>/sessions/<pid>.json. With
//                         HATS_FAKE_SPAWN it goes to the child: a terminal hosts
//                         a session rather than being one.
//   HATS_FAKE_TIMESTAMPS  procStart, startedAt, both (default) or none
//   HATS_FAKE_STALE       seconds to shift those timestamps into the past
//   HATS_FAKE_SPAWN       a program to start as a child, sharing stdin and stdout
//   HATS_FAKE_PROBE       lookup:<mach service>, apple-event or register:<app path>.
//                         Prints the call's status and exits, instead of all of the
//                         below, so the guard's tests can see what its rules deny.
//
// Prints `ready <pid>` once set up, then blocks on stdin and exits at EOF, so a
// crashed test process takes its fakes down with it. A host outlives its child, so
// when the host is gone both are.
//
// Inside a bundle whose ID is `dev.wearhats.e2e.fake-claude` it is a real regular app
// instead, because Launch Services starts it with no test on the other end. It writes
// `report-<pid>.json` next to the bundle, then runs until asked to quit, for at most
// two minutes.

let environment = ProcessInfo.processInfo.environment
let pid = getpid()

/// Reports from inside the run loop, so whoever reads the report can already find
/// this process as a regular app, and activate it or ask it to quit.
@MainActor func runAsApp() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    DispatchQueue.main.async {
        let report: [String: Any] = [
            "pid": pid, "arguments": Array(CommandLine.arguments.dropFirst()),
            "configDir": environment["CLAUDE_CONFIG_DIR"] ?? NSNull(),
        ]
        let directory = Bundle.main.bundleURL.deletingLastPathComponent()
        do {
            // Atomic, so a test polling for the file never reads half of it.
            try JSONSerialization.data(withJSONObject: report).write(to: directory.appending(path: "report-\(pid).json"), options: .atomic)
        } catch {
            fatalError("hats-e2e-fake: \(error)")
        }
    }
    Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in exit(0) }
    app.run()
    exit(0)
}

/// Swift doesn't import `servers/bootstrap.h`.
@_silgen_name("bootstrap_look_up")
func bootstrapLookUp(_ bootstrap: mach_port_t, _ service: UnsafePointer<CChar>, _ port: UnsafeMutablePointer<mach_port_t>) -> kern_return_t

/// `ascr/gdte`, spelled as its four-char codes because Swift doesn't import them, asks
/// for an app's scripting dictionary. It changes nothing and raised no Automation
/// prompt when measured, unlike an event that drives the app.
func sendReadOnlyAppleEvent() -> OSStatus {
    var target = AEAddressDesc()
    var event = AppleEvent()
    var reply = AppleEvent()
    let bundleID = Array("com.apple.finder".utf8)
    guard AECreateDesc(DescType(typeApplicationBundleID), bundleID, bundleID.count, &target) == noErr,
        AECreateAppleEvent(
            AEEventClass(0x6173_6372), AEEventID(0x6764_7465), &target, AEReturnID(kAutoGenerateReturnID),
            AETransactionID(kAnyTransactionID), &event) == noErr
    else { fatalError("hats-e2e-fake: couldn't build the Apple event") }
    return AESendMessage(&event, &reply, AESendMode(kAEWaitReply), 300)
}

func runProbe(_ probe: String) -> Never {
    let status: Int32
    if probe == "apple-event" {
        status = sendReadOnlyAppleEvent()
    } else if probe.hasPrefix("lookup:") {
        var port = mach_port_t()
        status = bootstrapLookUp(bootstrap_port, String(probe.dropFirst("lookup:".count)), &port)
    } else if probe.hasPrefix("register:") {
        status = LSRegisterURL(URL(filePath: String(probe.dropFirst("register:".count))) as CFURL, true)
    } else {
        fatalError("hats-e2e-fake: unknown probe \(probe)")
    }
    print(status)
    exit(0)
}

if let probe = environment["HATS_FAKE_PROBE"] { runProbe(probe) }
if Bundle.main.bundleIdentifier == "dev.wearhats.e2e.fake-claude" { runAsApp() }

func kernelStartTime() -> Date {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { fatalError("no kernel start time for \(pid)") }
    let start = info.kp_proc.p_un.__p_starttime
    return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
}

/// The format Claude Code writes: `ctime`, which pads a single-digit day with a space.
func ctimeString(_ date: Date) -> String {
    var seconds = time_t(date.timeIntervalSince1970)
    var parts = tm()
    localtime_r(&seconds, &parts)
    var buffer = [CChar](repeating: 0, count: 64)
    let count = strftime(&buffer, buffer.count, "%a %b %e %H:%M:%S %Y", &parts)
    return String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

func writeRegistryEntry(fields: String) throws {
    guard var entry = try JSONSerialization.jsonObject(with: Data(fields.utf8)) as? [String: Any] else {
        fatalError("HATS_FAKE_SESSION is not a JSON object: \(fields)")
    }
    let stale = TimeInterval(environment["HATS_FAKE_STALE"] ?? "0") ?? 0
    let timestamps = environment["HATS_FAKE_TIMESTAMPS"] ?? "both"
    entry["pid"] = pid
    if timestamps == "startedAt" || timestamps == "both" {
        entry["startedAt"] = (Date.now.timeIntervalSince1970 - stale) * 1_000
    }
    if timestamps == "procStart" || timestamps == "both" {
        entry["procStart"] = ctimeString(kernelStartTime().addingTimeInterval(-stale))
    }
    let configDir = environment["CLAUDE_CONFIG_DIR"] ?? "\(environment["HOME"] ?? "")/.claude"
    let directory = URL(filePath: "\(configDir)/sessions", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: entry).write(to: directory.appending(path: "\(pid).json"))
}

func spawnChild(_ path: String) throws -> Process {
    var childEnvironment = environment
    childEnvironment["HATS_FAKE_SPAWN"] = nil
    let child = Process()
    child.executableURL = URL(filePath: path)
    child.environment = childEnvironment
    child.standardInput = FileHandle.standardInput
    child.standardOutput = FileHandle.standardOutput
    try child.run()
    return child
}

var child: Process?
do {
    if let path = environment["HATS_FAKE_SPAWN"] {
        child = try spawnChild(path)
    } else if let fields = environment["HATS_FAKE_SESSION"] {
        try writeRegistryEntry(fields: fields)
    }
} catch {
    fatalError("hats-e2e-fake: \(error)")
}

FileHandle.standardOutput.write(Data("ready \(pid)\n".utf8))
while (try? FileHandle.standardInput.read(upToCount: 4096))?.isEmpty == false {}
child?.waitUntilExit()
