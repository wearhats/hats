import Foundation
import Testing

/// Every case must print nothing on stdout and change nothing in the sandbox.
struct Refusal: Sendable, CustomTestStringConvertible {
    let name: String
    let exit: Int32
    let stderr: String
    let arguments: @Sendable (E2ESandbox) throws -> [String]

    init(_ name: String, exit: Int32, stderr: String, _ arguments: @escaping @Sendable (E2ESandbox) throws -> [String]) {
        self.name = name
        self.exit = exit
        self.stderr = stderr
        self.arguments = arguments
    }

    init(_ name: String, exit: Int32, stderr: String, argv: [String]) {
        self.init(name, exit: exit, stderr: stderr) { _ in argv }
    }

    var testDescription: String { name }

    static let all: [Refusal] = [
        Refusal("add: invalid name", exit: 64, stderr: "invalid profile name 'BAD'", argv: ["add", "BAD"]),
        Refusal("add: default", exit: 64, stderr: "'default' is the stock Claude install", argv: ["add", "default"]),
        Refusal("add: bad colour", exit: 64, stderr: "invalid color 'nope'", argv: ["add", "t1", "--color", "nope"]),
        Refusal("add: bad icon", exit: 64, stderr: "nope", argv: ["add", "t1", "--icon", "nope"]),
        Refusal("add: label with a slash", exit: 64, stderr: "invalid label 'a/b'", argv: ["add", "t1", "--label", "a/b"]),
        Refusal("add: empty label", exit: 64, stderr: "invalid label ''", argv: ["add", "t1", "--label", ""]),
        Refusal("add: label taken, ignoring case", exit: 1, stderr: "already used by profile 'work'") { sandbox in
            try sandbox.addProfile("work", label: "Work")
            return ["add", "t1", "--label", "WORK"]
        },
        Refusal("add: invalid shortcut", exit: 64, stderr: "invalid shortcut 'W'", argv: ["add", "t1", "--shortcut", "W"]),
        Refusal(
            "add: shortcut and no shortcut", exit: 64, stderr: "--shortcut or --no-shortcut",
            argv: ["add", "t1", "--shortcut", "w", "--no-shortcut"]),
        Refusal(
            "add: shortcut is default", exit: 64, stderr: "'default' can't be a shortcut", argv: ["add", "t1", "--shortcut", "default"]),
        Refusal("add: shortcut is another name", exit: 1, stderr: "is the name of profile 'work'") { sandbox in
            try sandbox.addProfile("work")
            return ["add", "t1", "--shortcut", "work"]
        },
        Refusal("add: shortcut taken", exit: 1, stderr: "already used by profile 'work'") { sandbox in
            try sandbox.addProfile("work", shortcut: "w")
            return ["add", "t1", "--shortcut", "w"]
        },
        Refusal("add: name is another profile's shortcut", exit: 1, stderr: "is the shortcut of profile 'work'") { sandbox in
            try sandbox.addProfile("work", shortcut: "w")
            return ["add", "w"]
        },
        Refusal("reset: shortcut", exit: 64, stderr: "this command takes the full name: work") { sandbox in
            try sandbox.addProfile("work", shortcut: "w")
            return ["reset", "w", "--yes"]
        },
        Refusal("rm: shortcut", exit: 64, stderr: "this command takes the full name: work") { sandbox in
            try sandbox.addProfile("work", shortcut: "w")
            return ["rm", "w", "--purge", "--yes"]
        },
        Refusal("add: shortcut is its own name", exit: 64, stderr: "the profile's own name", argv: ["add", "t1", "--shortcut", "t1"]),
        Refusal("reset: ambiguous shortcut", exit: 1, stderr: "the shortcut 'w' is claimed by 'acme', 'work'") { sandbox in
            try sandbox.addProfile("acme", shortcut: "w")
            try sandbox.addProfile("work", shortcut: "w")
            return ["reset", "w", "--yes"]
        },
        Refusal("rm: ambiguous shortcut", exit: 1, stderr: "the shortcut 'w' is claimed by 'acme', 'work'") { sandbox in
            try sandbox.addProfile("acme", shortcut: "w")
            try sandbox.addProfile("work", shortcut: "w")
            return ["rm", "w", "--purge", "--yes"]
        },
        Refusal("reset: shortcut of an unreadable profile", exit: 1, stderr: "cannot check whether 'w' is a shortcut") { sandbox in
            try sandbox.addProfile("work", shortcut: "w")
            try sandbox.write("{ not json", to: "\(sandbox.hatsHome)/profiles/work/profile.json")
            return ["reset", "w", "--yes"]
        },
        Refusal("rm: shortcut of an unreadable profile", exit: 1, stderr: "cannot check whether 'w' is a shortcut") { sandbox in
            try sandbox.addProfile("work", shortcut: "w")
            try sandbox.write("{ not json", to: "\(sandbox.hatsHome)/profiles/work/profile.json")
            return ["rm", "w", "--purge", "--yes"]
        },
        Refusal("ps: ambiguous shortcut", exit: 1, stderr: "the shortcut 'w' is claimed by 'acme', 'work'") { sandbox in
            try sandbox.addProfile("acme", shortcut: "w")
            try sandbox.addProfile("work", shortcut: "w")
            return ["ps", "--profile", "w"]
        },
        Refusal("ps: unreadable profile", exit: 1, stderr: "cannot read") { sandbox in
            try sandbox.addProfile("work")
            try sandbox.write("{ not json", to: "\(sandbox.hatsHome)/profiles/work/profile.json")
            return ["ps", "--profile", "work"]
        },
        Refusal("ps: shortcut of an unreadable profile", exit: 1, stderr: "cannot check whether 'w' is a shortcut") { sandbox in
            try sandbox.addProfile("work", shortcut: "w")
            try sandbox.write("{ not json", to: "\(sandbox.hatsHome)/profiles/work/profile.json")
            return ["ps", "--profile", "w"]
        },
        Refusal("add: adopted dir is missing", exit: 1, stderr: "is not an existing directory") { sandbox in
            ["add", "t1", "--code-dir", "\(sandbox.root)/missing"]
        },
        Refusal("add: adopted dir is the default", exit: 64, stderr: "is the default profile's config dir") { sandbox in
            try sandbox.makeDirectory(sandbox.defaultConfigDir)
            return ["add", "t1", "--code-dir", sandbox.defaultConfigDir]
        },
        Refusal("add: adopted dir is inside HATS_HOME", exit: 64, stderr: "is inside hats' own data directory") { sandbox in
            let inside = "\(sandbox.hatsHome)/inside"
            try sandbox.makeDirectory(inside)
            return ["add", "t1", "--code-dir", inside]
        },
        Refusal("add: adopted dir has another owner", exit: 1, stderr: "is already used by profile 'other'") { sandbox in
            let adopted = "\(sandbox.root)/adopted"
            try sandbox.addProfile("other", adopting: adopted)
            return ["add", "t1", "--code-dir", adopted]
        },

        Refusal("open: nothing named", exit: 64, stderr: "give profile names or --all", argv: ["open"]),
        Refusal("open: names and --all", exit: 64, stderr: "give profile names or --all", argv: ["open", "t1", "--all"]),
        Refusal("open: unknown", exit: 1, stderr: "no profile named 'ghost'", argv: ["open", "ghost"]),
        Refusal("open: invalid name", exit: 64, stderr: "invalid profile name 'BAD'", argv: ["open", "BAD"]),

        Refusal("ps: invalid filter", exit: 64, stderr: "invalid profile name 'BAD'", argv: ["ps", "--profile", "BAD"]),

        Refusal("reset: default", exit: 64, stderr: "the default profile is the stock Claude install", argv: ["reset", "default"]),
        Refusal("reset: unknown", exit: 1, stderr: "no profile named 'ghost'", argv: ["reset", "ghost"]),

        Refusal("rm: nothing named", exit: 64, stderr: "give profile names or --all", argv: ["rm"]),
        Refusal("rm: names and --all", exit: 64, stderr: "give profile names or --all", argv: ["rm", "t1", "--all"]),
        Refusal("rm: default", exit: 64, stderr: "hats never removes it", argv: ["rm", "default"]),
        Refusal("rm: unknown", exit: 1, stderr: "no profile named 'ghost'", argv: ["rm", "ghost"]),

        Refusal("launcher rebuild: unknown", exit: 1, stderr: "no profile named 'ghost'", argv: ["launcher", "rebuild", "ghost"]),
        Refusal("launcher copy: unknown", exit: 1, stderr: "no profile named 'ghost'", argv: ["launcher", "copy", "ghost"]),
        Refusal("launcher copy: no launcher", exit: 1, stderr: "no launcher for 't1'") { sandbox in
            try sandbox.addProfile("t1")
            return ["launcher", "copy", "t1"]
        },

        Refusal("dock pin: default", exit: 64, stderr: "Claude.app itself is pinned the usual way", argv: ["dock", "pin", "default"]),
        Refusal("dock pin: unknown", exit: 1, stderr: "no profile named 'ghost'", argv: ["dock", "pin", "ghost"]),
        Refusal("dock pin: no launcher", exit: 1, stderr: "no launcher for 't1'") { sandbox in
            try sandbox.addProfile("t1")
            return ["dock", "pin", "t1"]
        },
        Refusal("dock unpin: unknown", exit: 1, stderr: "no profile named 'ghost'", argv: ["dock", "unpin", "ghost"]),

        Refusal("setup: no terminal", exit: 64, stderr: "needs a terminal", argv: ["setup"]),

        Refusal("env: unknown", exit: 1, stderr: "no profile named 'ghost'", argv: ["env", "ghost"]),
        Refusal("env: invalid name", exit: 64, stderr: "invalid profile name 'BAD'", argv: ["env", "BAD"]),
        Refusal("env: unknown shell", exit: 64, stderr: "nope", argv: ["env", "default", "--shell", "nope"]),

        Refusal("exec: unknown", exit: 1, stderr: "no profile named 'ghost'", argv: ["exec", "ghost", "--", "/usr/bin/true"]),
        Refusal("exec: invalid name", exit: 64, stderr: "invalid profile name 'BAD'", argv: ["exec", "BAD", "--", "/usr/bin/true"]),
        Refusal("run: unknown", exit: 1, stderr: "no profile named 'ghost'", argv: ["run", "ghost"]),
        Refusal("run: invalid name", exit: 64, stderr: "invalid profile name 'BAD'", argv: ["run", "BAD"]),
    ]
}

@Suite("Refusals", .tags(.e2e))
struct RefusalTests {
    @Test(arguments: Refusal.all)
    func refusalsExitWithTheDocumentedCode(refusal: Refusal) throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(try refusal.arguments(sandbox))

        #expect(result.exit == refusal.exit, "\(result)")
        #expect(!result.wasKilledBySignal, "\(result)")
        #expect(result.stderr.contains(refusal.stderr), "\(result)")
        #expect(result.stdout.isEmpty, "\(result)")
    }

    @Test(arguments: Refusal.all)
    func refusalsWriteNothing(refusal: Refusal) throws {
        let sandbox = try E2ESandbox()
        let arguments = try refusal.arguments(sandbox)
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(arguments)

        #expect(result.exit == refusal.exit, "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }

    @Test func refusalsPrintTheMessageThenTheHintOnStderr() throws {
        let result = try E2ESandbox().hats(["env", "ghost"])

        #expect(result.stderr == "hats: no profile named 'ghost'\nhint: create it with: hats add ghost\n", "\(result)")
        #expect(result.stdout.isEmpty, "\(result)")
    }

    @Test func dryRunForcedRemoveChangesNothing() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1")
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["rm", "t1", "--force", "--dry-run"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "Would remove the launcher of 't1'.\n", "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }

    @Test func refusesAProfileFromANewerSchema() throws {
        let sandbox = try E2ESandbox()
        try sandbox.addProfile("t1", schemaVersion: 999)

        let result = try sandbox.hats(["env", "t1"])

        #expect(result.exit == 1, "\(result)")
        #expect(result.stderr == "hats: profile 't1' was written by a newer hats (schema 999)\nhint: upgrade hats\n", "\(result)")
        #expect(result.stdout.isEmpty, "\(result)")
    }

    @Test(arguments: [["open", "--all"], ["dock", "pin"]])
    func havingNoProfilesIsNotAnError(arguments: [String]) throws {
        let result = try E2ESandbox().hats(arguments)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout == "No profiles yet. Create one with: hats add <name>\n", "\(result)")
    }

    @Test func rebuildingLaunchersWithNoProfilesDoesNothing() throws {
        let sandbox = try E2ESandbox()
        let before = try sandbox.snapshot()

        let result = try sandbox.hats(["launcher", "rebuild"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.isEmpty, "\(result)")
        #expect(try sandbox.snapshot() == before, "\(result)")
    }
}
