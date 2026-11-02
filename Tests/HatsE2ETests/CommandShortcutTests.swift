import Foundation
import Testing

/// Everything here stops at `--help`, so no command reaches a process scan or
/// an OS call, and each case pins the exact command its shortcut resolves to.
@Suite("Command shortcuts", .tags(.e2e))
struct CommandShortcutTests {
    @Test(arguments: [("r", "run"), ("o", "open"), ("x", "exec"), ("f", "focus")])
    func shortcutResolvesToItsCommand(shortcut: String, command: String) throws {
        let sandbox = try E2ESandbox()

        let viaShortcut = try sandbox.hats([shortcut, "--help"])
        let viaCommand = try sandbox.hats([command, "--help"])

        #expect(viaShortcut.exit == 0, "\(viaShortcut)")
        #expect(viaShortcut.stdout.contains("USAGE: hats \(command) "), "\(viaShortcut)")
        #expect(viaShortcut.stdout == viaCommand.stdout, "\(viaShortcut)")
    }

    @Test func helpListsEveryShortcut() throws {
        let result = try E2ESandbox().hats(["--help"])

        for label in ["run, r", "open, o", "exec, x", "focus, f"] {
            #expect(result.stdout.contains(label), "\(result)")
        }
    }

    /// Design rule 5. `helpListsEveryShortcut` pins the row format this relies on.
    @Test func commandsThatRemoveOrQuitHaveNoOneLetterShortcut() throws {
        let result = try E2ESandbox().hats(["--help"])

        #expect(result.stdout.firstMatch(of: /\b(rm|reset|dedupe)(, \w+)*, \w\b/) == nil, "\(result)")
    }
}
