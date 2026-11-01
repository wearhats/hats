import Foundation
import Testing

/// A guard that silently stopped working would make every other safety claim
/// empty, so each rule is exercised here, against decoys only.
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
