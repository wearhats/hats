import Foundation
import Testing

/// A half-configured sandbox must stop before it can fall through to the real
/// thing, so every case exits 1 and changes nothing.
@Suite("Test mode fails closed", .tags(.e2e))
struct TestModeTests {
    struct Misconfiguration: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let stderr: String
        var removing: Set<String> = []
        var environment: @Sendable (E2ESandbox) throws -> [String: String] = { _ in [:] }
    }

    static let misconfigurations: [Misconfiguration] = [
        .init(testDescription: "the dir is missing", stderr: "not an existing directory") { sandbox in
            ["HATS_TEST_SANDBOX": "\(sandbox.root)/missing"]
        },
        .init(testDescription: "the dir is empty", stderr: "not an existing directory") { _ in ["HATS_TEST_SANDBOX": ""] },
        .init(testDescription: "the dir is a file", stderr: "not an existing directory") { sandbox in
            try sandbox.write("", to: "\(sandbox.root)/file")
            return ["HATS_TEST_SANDBOX": "\(sandbox.root)/file"]
        },
        .init(testDescription: "the dir is the filesystem root", stderr: "must not contain the real home") { _ in
            ["HATS_TEST_SANDBOX": "/"]
        },
        .init(testDescription: "the dir contains the real home", stderr: "must not contain the real home") { _ in
            ["HATS_TEST_SANDBOX": (SeatbeltGuard.realHome as NSString).deletingLastPathComponent]
        },
        .init(testDescription: "the dir has no marker file", stderr: "has no .hats-test-sandbox file") { sandbox in
            try sandbox.makeDirectory("\(sandbox.root)/unmarked/home")
            return ["HATS_TEST_SANDBOX": "\(sandbox.root)/unmarked", "HOME": "\(sandbox.root)/unmarked/home"]
        },
        .init(testDescription: "HOME is unset", stderr: "needs HOME", removing: ["HOME"]),
        .init(testDescription: "HATS_HOME is unset", stderr: "needs HATS_HOME", removing: ["HATS_HOME"]),
        .init(testDescription: "HATS_LAUNCHER_DIR is unset", stderr: "needs HATS_LAUNCHER_DIR", removing: ["HATS_LAUNCHER_DIR"]),
        .init(testDescription: "HOME is outside", stderr: "HOME is outside") { _ in ["HOME": "/tmp/hats-e2e-outside"] },
        .init(testDescription: "HATS_HOME is outside", stderr: "HATS_HOME is outside") { _ in ["HATS_HOME": "/tmp/hats-e2e-outside"] },
        .init(testDescription: "HATS_LAUNCHER_DIR is outside", stderr: "HATS_LAUNCHER_DIR is outside") { _ in
            ["HATS_LAUNCHER_DIR": "/tmp/hats-e2e-outside"]
        },
        .init(testDescription: "HATS_DEFAULT_CONFIG_DIR is outside", stderr: "HATS_DEFAULT_CONFIG_DIR is outside") { _ in
            ["HATS_DEFAULT_CONFIG_DIR": "/tmp/hats-e2e-outside"]
        },
        .init(testDescription: "HATS_CLAUDE_APP is outside", stderr: "HATS_CLAUDE_APP is outside") { _ in
            ["HATS_CLAUDE_APP": "/Applications/Claude.app"]
        },
        .init(testDescription: "HATS_CLAUDE_BIN is outside", stderr: "HATS_CLAUDE_BIN is outside") { _ in ["HATS_CLAUDE_BIN": "/bin/bash"]
        },
        .init(testDescription: "a symlink leads HATS_HOME outside", stderr: "HATS_HOME is outside") { sandbox in
            let link = "\(sandbox.root)/escape"
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/tmp")
            return ["HATS_HOME": "\(link)/hats-e2e-outside"]
        },
        .init(testDescription: "a dangling symlink hides where HATS_HOME goes", stderr: "HATS_HOME is outside") { sandbox in
            let link = "\(sandbox.root)/dangling"
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/tmp/hats-e2e-missing-\(UUID().uuidString)")
            return ["HATS_HOME": link]
        },
        .init(testDescription: "the Desktop folder is a symlink out", stderr: "the Desktop folder is outside") { sandbox in
            try FileManager.default.createSymbolicLink(atPath: "\(sandbox.home)/Desktop", withDestinationPath: "/tmp")
            return [:]
        },
        .init(testDescription: "a profile's dir is a symlink out", stderr: "the Desktop dir of 't1' is outside") { sandbox in
            let desktop = "\(sandbox.profileDir("t1"))/desktop"
            try FileManager.default.removeItem(atPath: desktop)
            try FileManager.default.createSymbolicLink(atPath: desktop, withDestinationPath: "/tmp")
            return [:]
        },
        .init(testDescription: "the stand-ins' dir is a symlink out", stderr: "the stand-ins' dir is outside") { sandbox in
            try FileManager.default.createSymbolicLink(atPath: sandbox.testDir, withDestinationPath: "/tmp")
            return [:]
        },
        .init(testDescription: "a stored adopted dir is outside", stderr: "the code dir of 'adopter' is outside") { sandbox in
            try sandbox.addProfile("adopter", adopting: "\(sandbox.root)/adopted")
            try sandbox.recordAdoptedDir("/tmp/hats-e2e-outside", inProfile: "adopter")
            return [:]
        },
        .init(testDescription: "dot-dots climb out of a missing dir", stderr: "HATS_HOME is outside") { sandbox in
            ["HATS_HOME": "\(sandbox.root)/missing/../../../hats-e2e-outside"]
        },
    ]

    @Test(arguments: misconfigurations)
    func refusesToStart(misconfiguration: Misconfiguration) throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")
        let environment = try misconfiguration.environment(sandbox)
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["ls"], environment: environment, removing: misconfiguration.removing)

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains(misconfiguration.stderr), "\(result)")
        #expect(result.stderr.contains("hint: HATS_TEST_SANDBOX is only for hats' own tests"), "\(result)")
        #expect(result.stdout.isEmpty, "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }

    @Test func aLauncherLinkedInFromOutsideStopsEverything() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "t1"]).exit == 0)
        let outside = FileManager.default.temporaryDirectory.path(percentEncoded: false) + "hats-e2e-outside-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: outside) }
        try FileManager.default.moveItem(atPath: sandbox.launcher("T1"), toPath: outside)
        try FileManager.default.createSymbolicLink(atPath: sandbox.launcher("T1"), withDestinationPath: outside)

        let result = try sandbox.hats(["ls"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("the launcher of 't1' is outside"), "\(result)")
    }

    @Test func aRecordedLauncherCopyOutsideStopsEverything() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "t1"]).exit == 0)
        let outside = "/tmp/hats-e2e-outside-\(UUID().uuidString)/Claude (T1).app"
        let marker = "\(sandbox.launcher("T1"))/Contents/Resources/hats-launcher.json"
        var object = try sandbox.marker(in: sandbox.launcher("T1"))
        object["copies"] = [outside]
        try sandbox.write(String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self), to: marker)

        let result = try sandbox.hats(["rm", "t1"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("a recorded copy of 't1' is outside"), "\(result)")
        #expect(sandbox.exists(sandbox.launcher("T1")))
    }

    @Test func runRefusesAClaudeFoundOnPathOutside() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")
        let dir = "\(sandbox.root)/on-path"
        try sandbox.makeDirectory(dir)
        try FileManager.default.createSymbolicLink(atPath: "\(dir)/claude", withDestinationPath: "/bin/echo")

        let result = try sandbox.hats(["run", "t1"], environment: ["PATH": dir])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("the claude CLI is outside"), "\(result)")
        #expect(result.stdout.isEmpty, "\(result)")
    }

    @Test(arguments: [["add", "t1", "--code-dir", ""], ["launcher", "copy", "t1", "--to", ""]])
    func anEmptyDirectoryArgumentIsAUsageError(arguments: [String]) throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1", label: "T1")
        #expect(try sandbox.hats(["launcher", "rebuild", "t1"]).exit == 0)
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(arguments)

        #expect(result.exit == 64, "\(result)")
        #expect(result.stderr.contains("needs a directory"), "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }

    @Test(arguments: [["env", "t1"], ["exec", "t1", "--", "/usr/bin/true"], ["run", "t1"], ["doctor"], ["dock", "pin"]])
    func everyCommandRefuses(arguments: [String]) throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")

        let result = try sandbox.hats(arguments, environment: ["HATS_HOME": "/tmp/hats-e2e-outside"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("HATS_HOME is outside"), "\(result)")
    }

    @Test(arguments: ["/tmp/hats-e2e-outside", "~root/hats-e2e-outside"])
    func refusesToAdoptADirOutside(path: String) throws {
        let sandbox = try E2ESandbox()
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["add", "t1", "--code-dir", path])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("--code-dir is outside"), "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }

    @Test(arguments: ["/tmp/hats-e2e-outside", "~root/hats-e2e-outside"])
    func refusesToCopyALauncherOutside(path: String) throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "t1"]).exit == 0)
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["launcher", "copy", "t1", "--to", path])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("--to is outside"), "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }

    @Test func aPathInsideIsAllowedEvenIfItDoesNotExistYet() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "t1"]).exit == 0)
        let destination = "\(sandbox.root)/not/yet/there"

        let result = try sandbox.hats(["launcher", "copy", "t1", "--to", destination])

        #expect(result.exit == 0, "\(result)")
        #expect(sandbox.exists("\(destination)/Claude (T1).app"))
    }

    @Test func otherProcessesAreInvisible() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(["ps", "--json"])

        #expect(result.exit == 0, "\(result)")
        #expect(try sandbox.json(result).isEmpty, "\(result)")
    }
}

@Suite("A tilde means this HOME", .tags(.e2e))
struct TildeTests {
    @Test func adoptingATildePathStaysInHome() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeDirectory("\(sandbox.home)/.claude-work")

        let result = try sandbox.hats(["add", "work", "--code-dir", "~/.claude-work"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("code      \(sandbox.home)/.claude-work (adopted)"), "\(result)")
    }

    @Test func copyingToATildePathStaysInHome() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "t1"]).exit == 0)

        let result = try sandbox.hats(["launcher", "copy", "t1", "--to", "~/x"])

        #expect(result.exit == 0, "\(result)")
        #expect(sandbox.exists("\(sandbox.home)/x/Claude (T1).app"), "\(result)")
    }

    @Test func aTildeInHatsHomeStaysInHome() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(["add", "t1"], environment: ["HATS_HOME": "~/hats-data"])

        #expect(result.exit == 0, "\(result)")
        #expect(sandbox.exists("\(sandbox.home)/hats-data/profiles/t1/profile.json"), "\(result)")
    }

    @Test func aRelativeAdoptedDirIsRecordedAsAbsolute() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeDirectory("\(sandbox.root)/relative-dir")

        let result = try sandbox.hats(["add", "t1", "--code-dir", "relative-dir"])

        #expect(result.exit == 0, "\(result)")
        let metadata = try #require(
            try JSONSerialization.jsonObject(with: Data(sandbox.read("\(sandbox.profileDir("t1"))/profile.json").utf8)) as? [String: Any])
        #expect(metadata["externalCodeDir"] as? String == "\(sandbox.root)/relative-dir", "\(result)")
    }

    @Test func aStoredLabelThatLeavesTheLauncherDirMakesTheProfileUnreadable() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1", label: "../../escaped")
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["launcher", "rebuild", "t1"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr.contains("invalid label"), "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }
}
