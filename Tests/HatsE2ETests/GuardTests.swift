import Foundation
import Testing

/// A guard that silently stopped working would make every other safety claim
/// empty, so each rule is exercised here. Nothing here changes anything real: file
/// rules use decoys, and the Launch Services and Apple event rules only ask. Whether
/// a real registration is stopped is proved in `DisposableHostTests`.
@Suite("Seatbelt guard", .tags(.e2e), .enabled(if: SeatbeltGuard.isAvailable || SeatbeltGuard.isRequired))
struct GuardTests {
    @Test func guardBlocksWritesOutsideTheSandbox() throws {
        let sandbox = try E2ESandbox()
        let outside = "\((sandbox.root as NSString).deletingLastPathComponent)/hats-e2e-outside-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: outside) }

        let result = try sandbox.guarded("/usr/bin/touch", [outside])

        #expect(result.exit != 0, "\(result)")
        #expect(result.stderr.contains("Operation not permitted"), "\(result)")
        #expect(!FileManager.default.fileExists(atPath: outside))
    }

    @Test func guardAllowsWritesInsideTheSandbox() throws {
        let sandbox = try E2ESandbox()
        let inside = "\(sandbox.root)/inside"

        let result = try sandbox.guarded("/usr/bin/touch", [inside])

        #expect(result.exit == 0, "\(result)")
        #expect(FileManager.default.fileExists(atPath: inside))
    }

    @Test(
        arguments: [
            ".claude/credentials",
            ".claude.json",
            ".claude-work/credentials",
            ".claude.work/credentials",
            ".claude_work/credentials",
            "Library/Application Support/Claude/config.json",
        ])
    func guardBlocksReadsOfClaudeData(relativePath: String) throws {
        let sandbox = try E2ESandbox()
        let decoyHome = "\(sandbox.root)/decoy-home"
        let decoy = "\(decoyHome)/\(relativePath)"
        try sandbox.write(sandbox.sentinel, to: decoy)

        let result = try sandbox.guarded("/bin/cat", [decoy], protectedHome: decoyHome)

        #expect(result.exit != 0, "\(result)")
        #expect(result.stderr.contains("Operation not permitted"), "\(result)")
        #expect(!sandbox.leaksSentinel(result), "\(result)")
    }

    @Test(arguments: [".clauderc", "claude/notes", "Library/Application Support/hats/profile.json"])
    func guardLeavesOtherFilesReadable(relativePath: String) throws {
        let sandbox = try E2ESandbox()
        let decoyHome = "\(sandbox.root)/decoy-home"
        let decoy = "\(decoyHome)/\(relativePath)"
        try sandbox.write("readable", to: decoy)

        let result = try sandbox.guarded("/bin/cat", [decoy], protectedHome: decoyHome)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "readable", "\(result)")
    }

    @Test func guardProtectsTheRealHomeByDefault() {
        let profile = SeatbeltGuard.profile(sandboxRoot: "/sandbox", protectedHome: SeatbeltGuard.realHome)

        #expect(SeatbeltGuard.realHome.hasPrefix("/"))
        #expect(profile.contains("(subpath \"\(SeatbeltGuard.realHome)/.claude\")"))
        #expect(profile.contains("(literal \"\(SeatbeltGuard.realHome)/.claude.json\")"))
    }

    @Test func guardBlocksPreferenceWrites() throws {
        let sandbox = try E2ESandbox()
        let decoyDomain = "dev.wearhats.e2e.decoy-\(UUID().uuidString)"

        let result = try sandbox.guarded("/usr/bin/defaults", ["write", decoyDomain, "key", "value"])
        defer {
            if result.exit == 0 {
                // Only reachable when the guard has failed: `defaults delete` alone leaves an empty plist behind.
                _ = try? CommandRunner.run(executable: "/usr/bin/defaults", arguments: ["delete", decoyDomain], environment: [:])
                try? FileManager.default.removeItem(atPath: "\(SeatbeltGuard.realHome)/Library/Preferences/\(decoyDomain).plist")
            }
        }

        #expect(result.exit != 0, "\(result)")
        #expect(result.stderr.contains("Could not write domain"), "\(result)")
    }

    @Test func guardBlocksSignalsToOtherProcesses() throws {
        let sandbox = try E2ESandbox()
        let target = Process()
        let targetStdin = Pipe()
        target.executableURL = URL(filePath: "/bin/cat")
        target.standardInput = targetStdin
        target.standardOutput = FileHandle.nullDevice
        try target.run()
        defer {
            try? targetStdin.fileHandleForWriting.close()
            target.waitUntilExit()
        }

        let result = try sandbox.guarded("/bin/kill", ["-TERM", String(target.processIdentifier)])

        #expect(result.exit != 0, "\(result)")
        #expect(result.stderr.contains("Operation not permitted"), "\(result)")
        #expect(target.isRunning)
    }

    /// curl words a blocked connection like a refused one, so this listens for real:
    /// the same request reaches the listener without the guard and fails with it.
    /// Connected but never answered, an unguarded curl hits its time limit (28).
    @Test func guardBlocksNetworkConnections() throws {
        let sandbox = try E2ESandbox()
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(listener) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(listener, generic, length) == 0 && listen(listener, 1) == 0 && getsockname(listener, generic, &length) == 0
            }
        }
        try #require(bound)
        let arguments = ["-sS", "--max-time", "1", "http://127.0.0.1:\(in_port_t(bigEndian: address.sin_port))/"]

        let unguarded = try CommandRunner.run(executable: "/usr/bin/curl", arguments: arguments, environment: [:])
        let guarded = try sandbox.guarded("/usr/bin/curl", arguments)

        #expect(unguarded.exit == 28, "\(unguarded)")
        #expect(guarded.exit == 7, "\(guarded)")
    }

    /// These services and Finder belong to the login session, so outside one, as over
    /// SSH, there's nothing to compare with. CI requires the guard, so it can't skip.
    private func succeedsWithoutTheGuard(_ probe: String) throws -> Bool {
        let unguarded = try FakeBinary.probe(probe)
        if !SeatbeltGuard.isRequired, unguarded != "0" { return false }
        #expect(unguarded == "0")
        return true
    }

    /// `1100` is `BOOTSTRAP_NOT_PRIVILEGED`.
    @Test func guardBlocksTheServiceThatWritesLaunchServices() throws {
        let service = "lookup:com.apple.lsd.modifydb"
        guard try succeedsWithoutTheGuard(service) else { return }

        #expect(try FakeBinary.probe(service, guardedBy: try E2ESandbox()) == "1100")
    }

    @Test func guardLeavesTheServiceThatReadsLaunchServices() throws {
        let service = "lookup:com.apple.lsd.mapdb"
        guard try succeedsWithoutTheGuard(service) else { return }

        #expect(try FakeBinary.probe(service, guardedBy: try E2ESandbox()) == "0")
    }

    /// `-600` is `procNotFound`, which would also mean Finder isn't running, so the
    /// same event has to reach it without the guard.
    @Test func guardBlocksAppleEvents() throws {
        guard try succeedsWithoutTheGuard("apple-event") else { return }

        #expect(try FakeBinary.probe("apple-event", guardedBy: try E2ESandbox()) == "-600")
    }

    @Test func guardLetsAProcessSignalItself() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.guarded("/bin/sh", ["-c", "kill -0 $$"])

        #expect(result.exit == 0, "\(result)")
    }

    @Test func guardIsRequiredWhenAskedFor() throws {
        #expect(throws: GuardUnavailable.self) { try SeatbeltGuard.shouldGuard(isAvailable: false, isRequired: true) }
        #expect(try !SeatbeltGuard.shouldGuard(isAvailable: false, isRequired: false))
        #expect(try SeatbeltGuard.shouldGuard(isAvailable: true, isRequired: true))
        #expect(try SeatbeltGuard.shouldGuard(isAvailable: true, isRequired: false))
        if SeatbeltGuard.isRequired {
            #expect(SeatbeltGuard.isAvailable, "the guard was required, and it can't apply on this machine")
        }
    }
}

@Suite("Harness checks", .tags(.e2e))
struct HarnessTests {
    @Test func theSentinelCheckCatchesALeak() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.guarded("/bin/cat", ["\(sandbox.home)/.claude.json"])

        #expect(sandbox.leaksSentinel(result), "\(result)")
    }

    @Test func aSnapshotSeesContentAndPermissionChanges() throws {
        let sandbox = try E2ESandbox()
        let file = "\(sandbox.root)/file"
        try sandbox.write("before", to: file)
        let original = try sandbox.snapshot()
        #expect(try sandbox.snapshot() == original)

        try sandbox.write("after!", to: file)
        #expect(try sandbox.snapshot() != original)

        try sandbox.write("before", to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file)
        #expect(try sandbox.snapshot() != original)
    }

    @Test func aHungCommandFailsOnTheTimeoutWithItsOutput() throws {
        #expect(throws: CommandTimedOut.self) {
            try CommandRunner.run(
                executable: "/bin/sh", arguments: ["-c", "echo started; exec /bin/sleep 30"], environment: [:], timeoutSeconds: 1)
        }
    }
}
