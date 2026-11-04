import Foundation
import Testing

/// Every case runs through `sandbox.doctor`, which also proves doctor changes nothing.
@Suite("hats doctor", .tags(.e2e))
struct DoctorCommandTests {
    @Test func warningsAloneExitZero() throws {
        let sandbox = try E2ESandbox()

        let (result, findings) = try sandbox.doctor(environment: try sandbox.withClaudeApp)

        #expect(result.exit == 0, "\(result)")
        #expect(findings.contains { $0["level"] as? String == "warn" }, "\(result)")
        #expect(!findings.contains { $0["level"] as? String == "fail" }, "\(result)")
    }

    @Test func aMissingClaudeAppFails() throws {
        let sandbox = try E2ESandbox()

        let (result, findings) = try sandbox.doctor()

        #expect(result.exit == 1, "\(result)")
        #expect(hasFinding(findings, level: "fail", check: "claude-app", containing: "not installed"), "\(result)")
    }

    @Test func anApplicationsLinkThatDanglesWarns() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeApplicationsDir()
        #expect(try sandbox.hats(["launcher", "link"]).exit == 0)
        try FileManager.default.removeItem(atPath: sandbox.launcherDir)

        let (result, findings) = try sandbox.doctor(environment: try sandbox.withClaudeApp)

        #expect(result.exit == 0, "\(result)")
        #expect(hasFinding(findings, level: "warn", check: "applications-link", containing: sandbox.applicationsLink), "\(result)")
    }

    @Test func aLauncherWhoseHatsIsGoneFails() throws {
        let sandbox = try E2ESandbox()
        let onPath = try sandbox.hatsOnPath()
        #expect(try sandbox.hats(["add", "work"], environment: onPath.environment).exit == 0)
        try FileManager.default.removeItem(atPath: onPath.path)

        let (result, findings) = try sandbox.doctor(environment: try sandbox.withClaudeApp)

        #expect(result.exit == 1, "\(result)")
        #expect(hasFinding(findings, level: "fail", check: "profile:work", containing: "missing hats binary"), "\(result)")
    }

    @Test func aMissingProfileDirFails() throws {
        let sandbox = try E2ESandbox()
        #expect(try sandbox.hats(["add", "work"]).exit == 0)
        try FileManager.default.removeItem(atPath: "\(sandbox.profileDir("work"))/desktop")

        let (result, findings) = try sandbox.doctor(environment: try sandbox.withClaudeApp)

        #expect(result.exit == 1, "\(result)")
        #expect(hasFinding(findings, level: "fail", check: "profile:work", containing: "missing"), "\(result)")
    }

    @Test func noClaudeCLIOnlyWarns() throws {
        let sandbox = try E2ESandbox()

        let (result, findings) = try sandbox.doctor(environment: try sandbox.withClaudeApp)

        #expect(result.exit == 0, "\(result)")
        #expect(hasFinding(findings, level: "warn", check: "claude-cli", containing: "not found"), "\(result)")
    }

    @Test func aSymlinkedDefaultConfigDirWarns() throws {
        let sandbox = try E2ESandbox()
        try sandbox.makeDirectory("\(sandbox.root)/elsewhere")
        try FileManager.default.createSymbolicLink(atPath: sandbox.defaultConfigDir, withDestinationPath: "\(sandbox.root)/elsewhere")

        let (result, findings) = try sandbox.doctor(environment: try sandbox.withClaudeApp)

        #expect(result.exit == 0, "\(result)")
        #expect(hasFinding(findings, level: "warn", check: "default-profile", containing: "is a symlink"), "\(result)")
    }

    @Test func noURLHandlerWarns() throws {
        let sandbox = try E2ESandbox()

        let (_, findings) = try sandbox.doctor(environment: try sandbox.withClaudeApp)

        #expect(hasFinding(findings, level: "warn", check: "sign-in", containing: "no app handles"))
    }

    @Test func anotherAppAsTheHandlerWarns() throws {
        let sandbox = try E2ESandbox()
        let other = try sandbox.makeApp(named: "Other", bundleID: "dev.wearhats.e2e.other")
        try sandbox.seedURLHandler(other)

        let (_, findings) = try sandbox.doctor(environment: try sandbox.withClaudeApp)

        #expect(hasFinding(findings, level: "warn", check: "sign-in", containing: "dev.wearhats.e2e.other"))
    }

    @Test func twoProfilesOnOneAccountWarn() throws {
        let sandbox = try E2ESandbox()
        for name in ["work", "other"] {
            let code = try sandbox.addProfile(name)
            try sandbox.write(#"{"oauthAccount":{"accountUuid":"same"}}"#, to: "\(code)/.claude.json")
        }

        let (_, findings) = try sandbox.doctor(environment: try sandbox.withClaudeApp)

        #expect(hasFinding(findings, level: "warn", check: "accounts", containing: "same Claude account"))
    }

    @Test func aSplitAccountWarns() throws {
        let sandbox = try E2ESandbox()
        let code = try sandbox.addProfile("work")
        try sandbox.write(#"{"oauthAccount":{"accountUuid":"code-side"}}"#, to: "\(code)/.claude.json")
        try sandbox.write(
            #"{"oauth:tokenCache":"\#(sandbox.sentinel)","lastKnownAccountUuid":"desktop-side"}"#,
            to: "\(sandbox.profileDir("work"))/desktop/config.json")

        let (_, findings) = try sandbox.doctor(environment: try sandbox.withClaudeApp)

        #expect(hasFinding(findings, level: "warn", check: "profile:work", containing: "different accounts"))
    }

    @Test func theTextReportHasBadgesAndHints() throws {
        let sandbox = try E2ESandbox()

        let result = try sandbox.hats(["doctor"], environment: try sandbox.withClaudeApp)

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("[ok]   claude-app: Claude Desktop 9.9.9 at"), "\(result)")
        #expect(result.stdout.contains("[warn] sign-in: no app handles"), "\(result)")
        #expect(result.stdout.contains("       open Claude.app once"), "\(result)")
    }
}
