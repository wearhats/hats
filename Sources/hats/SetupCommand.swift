import ArgumentParser
import Foundation
import HatsCore

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Guided setup: adopt the Claude Code dirs you already have and add a profile for your other account.",
        discussion: "Safe to re-run. Every step is also a plain command, printed as it runs."
    )

    func run() async throws {
        guard Prompt.isInteractive else {
            throw HatsError(
                .usage, "setup asks questions and needs a terminal",
                hint: "script it with: hats add <name> [--code-dir DIR] [--pin] [--open]")
        }
        let context = try Context()
        print("hats keeps your current Claude.app and ~/.claude as the 'default' profile and never changes them.")
        if let email = AccountProbe(layout: context.layout).info(for: context.store.defaultProfile).codeEmail {
            print("The default profile's claude CLI is signed in as \(email).")
        }

        var added: [Profile] = []
        let profiles = try context.readableProfiles()
        let instances = InstanceScanner(profiles: profiles, processes: context.processes).scan().instances
        for dir in AdoptionCandidates.find(layout: context.layout, profiles: profiles, instances: instances) {
            print("\nFound a Claude Code config dir you made yourself: \(dir.plainPath)")
            guard try Prompt.confirm("Turn it into a profile? Its login and history stay as they are.", default: true) else { continue }
            let suggested = try (ProfileName.suggested(forConfigDir: dir) ?? ProfileName("work")).unlessShortcut(in: profiles)
            let name = try ProfileName(Prompt.ask("Profile name", default: suggested?.rawValue))
            print("$ hats add \(name) --code-dir \(Output.shellQuote(dir.plainPath))")
            added.append(try create(name, adopting: dir, context: context))
        }

        let others = try context.readableProfiles().filter { !$0.isDefault }
        let wantsNew = try others.isEmpty || Prompt.confirm("\nAdd a profile for another account?", default: false)
        if wantsNew {
            let suggested = try ProfileName(others.isEmpty ? "personal" : "client").unlessShortcut(in: others)
            let name = try ProfileName(
                Prompt.ask("\nName for your other account (for example personal, work, acme)", default: suggested?.rawValue))
            print("$ hats add \(name)")
            added.append(try create(name, adopting: nil, context: context))
        }
        guard !added.isEmpty else { return printNextSteps() }

        let names = added.map(\.name.rawValue).joined(separator: " ")
        if try Prompt.confirm("\nPin the new launcher(s) to the Dock? This restarts the Dock.", default: true) {
            print("$ hats dock pin \(names)")
            try context.pinToDock(added, dedupeClaude: false)
        }
        try offerApplicationsLink(context: context)
        if try Prompt.confirm("Also put a copy on the Desktop?", default: false) {
            print("$ hats launcher copy \(names)")
            for profile in added {
                print(
                    "Copied to \(try context.launchers.copy(for: profile.name, to: context.layout.desktopFolder).plainPath)"
                )
            }
        }
        let needSignIn = added.filter { AccountProbe(layout: context.layout).info(for: $0).desktop != .signedIn }
        if !needSignIn.isEmpty,
            try Prompt.confirm("Open \(needSignIn.map(\.name.rawValue).joined(separator: ", ")) now to sign in?", default: true)
        {
            for profile in needSignIn {
                print("$ hats open \(profile.name)")
                try await context.open(profile)
            }
            print("\n" + Context.signInGuidance)
        }
        printNextSteps()
    }

    /// A failed link doesn't stop setup: the launchers work without it.
    private func offerApplicationsLink(context: Context) throws {
        let link = context.applicationsLink
        switch link.state() {
        case .ours, .notNeeded: return
        case .absent, .stale, .foreign: break
        }
        let question = "Also show them in Finder's Applications folder? This adds a link at \(link.url.plainPath)."
        guard try Prompt.confirm(question, default: true) else { return }
        print("$ hats launcher link")
        do {
            try context.linkApplications()
        } catch let error as HatsError {
            Output.printWarning(error.message, hint: error.hint)
        }
    }

    private func create(_ name: ProfileName, adopting dir: URL?, context: Context) throws -> Profile {
        if let dir { try context.testSandbox?.requireInside(dir.plainPath, what: "the dir to adopt") }
        let (profile, _) = try context.store.create(name, adoptingCodeDir: dir)
        print(
            "Launcher: \(try context.launchers.build(for: profile, hatsPath: context.hatsExecutablePath()).plainPath)"
        )
        return profile
    }

    private func printNextSteps() {
        print(
            """

            Everyday commands:
              hats ls                  profiles, sign-in state and accounts
              hats ps                  every running Claude, across profiles
              hats open <name>         focus or launch a profile's Claude Desktop (--all for every profile)
              hats run <name>          the claude CLI as that profile
              hats reset <name>        start a profile fresh if it opened on the wrong account
              hats doctor              check everything
            """)
    }
}
