import Foundation
import ArgumentParser
import HatsCore

/// Runs the daily release check alongside a command, then prints the notice
/// on stderr so stdout and `--json` stay unchanged.
struct UpdateNotifier {
    /// Long enough for a normal reply, short enough not to hold up a quick
    /// command. A slower reply is dropped, and the next check is a day later.
    static let replyWait: Duration = .milliseconds(800)

    let context: Context
    let check: UpdateCheck
    let refresh: Task<Void, Never>?

    static func start(for command: any ParsableCommand) -> UpdateNotifier? {
        // `run` and `exec` replace this process, so they would never print a notice.
        guard !(command is Run || command is Exec) else { return nil }
        // A sandbox that can't be contained is reported by the command itself.
        guard let context = try? Context(), let feed = context.touchpoints.releaseFeed,
            UpdateCheck.isEnabled(
                currentVersion: Hats.version, environment: context.environment, stderrIsTerminal: isatty(STDERR_FILENO) != 0)
        else { return nil }
        let check = UpdateCheck(layout: context.layout, feed: feed)
        let refresh = check.isDue() ? Task { await check.refresh() } : nil
        return UpdateNotifier(context: context, check: check, refresh: refresh)
    }

    func finish() async {
        if let refresh {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await refresh.value }
                group.addTask { try? await Task.sleep(for: Self.replyWait) }
                await group.next()
                group.cancelAll()
            }
        }
        let channel = InstallChannel.detect(executable: context.runningExecutable(), layout: context.layout)
        guard let notice = check.notice(currentVersion: Hats.version, channel: channel, home: context.layout.home.plainPath) else {
            return
        }
        var lines = ["", notice.message]
        if let command = notice.upgradeCommand { lines.append("To upgrade, run: \(command)") }
        lines.append(notice.releaseURL)
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}
