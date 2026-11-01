import ArgumentParser
import Foundation
import HatsCore

struct PS: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps",
        abstract: "List running Claude Desktop instances and Claude Code sessions across profiles."
    )

    @Flag(help: "Print JSON.")
    var json = false

    @Option(help: "Only show this profile.")
    var profile: String?

    func run() throws {
        let context = Context()
        let filter = try profile.map { try ProfileName($0) }
        let instances = InstanceScanner(profiles: try context.readableProfiles(), processes: context.processes).scan().instances
            .filter { filter == nil || $0.profile == filter }
        if json { return try Output.printJSON(instances) }
        guard !instances.isEmpty else { return print("No running Claude instances.") }
        let now = Date()
        Output.printTable(
            headers: ["PROFILE", "KIND", "PID", "STATUS", "AGE", "NAME", "CWD"],
            rows: instances.map { instance in
                [
                    instance.profile?.rawValue ?? "(\(Output.abbreviateHome(instance.dataDir)))",
                    instance.kind.rawValue,
                    String(instance.pid),
                    instance.status ?? "-",
                    Output.age(from: instance.startedAt, to: now),
                    instance.name ?? "-",
                    instance.cwd.map(Output.abbreviateHome) ?? "-",
                ]
            }
        )
    }
}

struct Focus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Bring a running instance forward: its Desktop window, or the terminal or IDE hosting a session."
    )

    @Argument(help: "PID or session name (see 'hats ps').")
    var target: String

    func run() async throws {
        let context = Context()
        let instances = InstanceScanner(profiles: try context.readableProfiles(), processes: context.processes).scan().instances
        let matches = instances.filter { String($0.pid) == target || $0.name == target || $0.sessionId == target }
        guard let instance = matches.first else {
            throw HatsError(.notFound, "no running instance matches '\(target)'", hint: "see: hats ps")
        }
        guard matches.count == 1 else {
            throw HatsError(.usage, "'\(target)' matches \(matches.count) instances", hint: "use the PID instead")
        }
        let resolver = HostAppResolver(processes: context.processes, control: context.control)
        guard let host = await resolver.hostApp(of: instance.pid), await context.control.activate(pid: host) else {
            throw HatsError(.environment, "cannot find a window for pid \(instance.pid)", hint: "it may run in a detached tmux or over SSH")
        }
        print("Focused pid \(host) hosting \(instance.kind.rawValue) pid \(instance.pid).")
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check the installation, profiles and running instances. Read-only.")

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let context = Context()
        let findings = HatsCore.Doctor(
            layout: context.layout,
            processes: context.processes,
            credentials: context.credentials,
            environment: context.environment
        ).run()
        if json {
            try Output.printJSON(findings)
        } else {
            for finding in findings {
                print("\(Output.badge(finding.level)) \(finding.check): \(finding.message)")
                if let hint = finding.hint, finding.level != .ok { print("       \(hint)") }
            }
        }
        if findings.contains(where: { $0.level == .fail }) { throw ExitCode.failure }
    }
}
