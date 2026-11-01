import Foundation
import Testing

@Suite("Binary contract", .tags(.e2e))
struct BinaryContractTests {
    @Test func versionPrintsASemanticVersion() throws {
        let result = try E2ESandbox().hats(["--version"])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.wholeMatch(of: /\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?\n/) != nil, "\(result)")
    }

    @Test func unknownSubcommandIsAUsageError() throws {
        let result = try E2ESandbox().hats(["no-such-command"])

        #expect(result.exit == 64, "\(result)")
        #expect(result.stdout.isEmpty, "\(result)")
        #expect(result.stderr.contains("no-such-command"), "\(result)")
    }

    @Test func noArgumentsPrintsHelp() throws {
        let result = try E2ESandbox().hats([])

        #expect(result.exit == 0, "\(result)")
        #expect(result.stdout.contains("USAGE: hats <subcommand>"), "\(result)")
        #expect(result.stdout.contains("SUBCOMMANDS:"), "\(result)")
    }

    /// Rule 2: this also covers branches no test reaches. The positive check
    /// keeps a broken `nm` parse from passing as "nothing forbidden".
    @Test func binaryImportsNoSecretReadingAPI() throws {
        let symbols = try importedSymbols()

        #expect(symbols.contains("_SecItemCopyMatching"))
        #expect(symbols.contains("_kSecReturnAttributes"))
        #expect(!symbols.contains("_kSecReturnData"))
        #expect(!symbols.contains("_kSecValueData"))
        #expect(!symbols.contains { $0.hasPrefix("_SecKeychainFind") })
    }

    @Test func binaryImportsNoHandlerChangingAPI() throws {
        let symbols = try importedSymbols()
        let binary = try Data(contentsOf: URL(filePath: try HatsBinary.path()))

        #expect(!symbols.contains { $0.hasPrefix("_LSSetDefault") })
        #expect(binary.range(of: Data("openApplicationAtURL:configuration:completionHandler:".utf8)) != nil)
        #expect(binary.range(of: Data("setDefaultApplicationAtURL".utf8)) == nil)
    }

    /// `nm` isn't hats, so it needs the caller's environment to find the
    /// toolchain, and it's slow on a debug binary, which is what the timeout allows for.
    private func importedSymbols() throws -> Set<String> {
        let result = try CommandRunner.run(
            executable: "/usr/bin/nm",
            arguments: ["-u", try HatsBinary.path()],
            environment: ProcessInfo.processInfo.environment,
            timeoutSeconds: 60
        )
        try #require(result.exit == 0, "\(result)")
        return Set(result.stdout.split(separator: "\n").map(String.init))
    }
}
