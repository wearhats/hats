import Foundation

struct GuardUnavailable: Error, CustomStringConvertible {
    var description: String {
        "HATS_E2E_REQUIRE_GUARD is set, but sandbox-exec can't apply a profile here, so these tests would run unprotected"
    }
}

/// Enforces the sandbox from outside hats, so a mistake in hats itself, such as
/// a future write to a path nobody thought of, is stopped rather than trusted.
enum SeatbeltGuard {
    private static let sandboxExec = "/usr/bin/sandbox-exec"

    static let isRequired = ProcessInfo.processInfo.environment["HATS_E2E_REQUIRE_GUARD"] == "1"

    static let isAvailable: Bool = {
        let result = try? CommandRunner.run(
            executable: sandboxExec, arguments: ["-p", "(version 1)(allow default)", "/usr/bin/true"], environment: [:])
        return result?.exit == 0
    }()

    /// The real one even when HOME is overridden, which is why it isn't read from the environment.
    static let realHome = canonicalPath(FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false))

    static func shouldGuard(isAvailable: Bool, isRequired: Bool) throws -> Bool {
        if !isAvailable, isRequired { throw GuardUnavailable() }
        return isAvailable
    }

    private static let warnsOnceWhenUnguarded: Void = {
        FileHandle.standardError.write(Data("warning: sandbox-exec is unavailable, so e2e tests run without the Seatbelt guard\n".utf8))
    }()

    static func wrap(
        executable: String, arguments: [String], sandboxRoot: String, protectedHome: String = realHome
    ) throws -> (executable: String, arguments: [String]) {
        guard try shouldGuard(isAvailable: isAvailable, isRequired: isRequired) else {
            _ = warnsOnceWhenUnguarded
            return (executable, arguments)
        }
        return (sandboxExec, ["-p", profile(sandboxRoot: sandboxRoot, protectedHome: protectedHome), executable] + arguments)
    }

    /// `protectedHome` is a parameter so the self-tests can prove the read rules
    /// on decoy files. A denied read of a missing path reports ENOENT, not EPERM,
    /// so the rules can only be observed on files that exist, and the real ones
    /// must never be opened.
    static func profile(sandboxRoot: String, protectedHome: String) -> String {
        let escapedHome = NSRegularExpression.escapedPattern(for: protectedHome)
        return """
            (version 1)
            (allow default)
            (deny file-write* (subpath "/"))
            (allow file-write*
              (subpath \(quoted(sandboxRoot)))
              (subpath \(quoted(foundationTemporaryItems)))
              (literal "/dev/null")
              (regex #"^/dev/(fd|tty)"))
            (deny file-read*
              (subpath \(quoted(protectedHome + "/.claude")))
              (literal \(quoted(protectedHome + "/.claude.json")))
              (regex #"^\(escapedHome)/\\.claude[-._]")
              (subpath \(quoted(protectedHome + "/Library/Application Support/Claude"))))
            (deny user-preference-write)
            ; (deny signal (target others)) doesn't stop a signal to another process (measured on macOS 27).
            (deny signal)
            (allow signal (target self))
            (deny appleevent-send)
            (deny mach-lookup (global-name "com.apple.lsd.modifydb"))
            """
    }

    /// Foundation's atomic writes stage the file here whatever TMPDIR says, then
    /// rename it into place, so hats can't write `profile.json` without it.
    static let foundationTemporaryItems: String = {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 else { return "/nonexistent" }
        return canonicalPath(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)) + "/TemporaryItems"
    }()

    private static func quoted(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Not `URL.resolvingSymlinksInPath`, which strips the `/private` prefix that
/// Seatbelt rules must match.
func canonicalPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}
