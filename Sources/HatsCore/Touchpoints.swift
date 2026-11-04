import Foundation

/// Every OS touchpoint a command can reach, chosen once in the CLI's composition
/// root. Nothing downstream defaults to a real implementation, so forgetting to
/// pass one is a compile error rather than a test that touches the real Dock.
public struct Touchpoints: Sendable {
    public let processes: any ProcessTable
    public let control: any AppControl
    public let credentials: any CredentialProbe
    public let dock: any DockPreferences
    public let discarder: Discarder
    public let registrar: AppRegistrar
    public let folderOpener: any FolderOpener
    public let urlSchemeHandler: @Sendable (String) -> URL?
    public let appSearch: ClaudeAppSearch
    /// `/Applications`, which Finder's sidebar calls Applications. `launcher link`
    /// puts the link to the launcher dir here.
    public let applicationsDir: URL
    /// `nil` turns the update check off.
    public let releaseFeed: (any ReleaseFeed)?

    public init(
        processes: any ProcessTable,
        control: any AppControl,
        credentials: any CredentialProbe,
        dock: any DockPreferences,
        discarder: Discarder,
        registrar: AppRegistrar,
        folderOpener: any FolderOpener,
        urlSchemeHandler: @escaping @Sendable (String) -> URL?,
        appSearch: ClaudeAppSearch,
        applicationsDir: URL,
        releaseFeed: (any ReleaseFeed)?
    ) {
        self.processes = processes
        self.control = control
        self.credentials = credentials
        self.dock = dock
        self.discarder = discarder
        self.registrar = registrar
        self.folderOpener = folderOpener
        self.urlSchemeHandler = urlSchemeHandler
        self.appSearch = appSearch
        self.applicationsDir = applicationsDir
        self.releaseFeed = releaseFeed
    }
}

#if os(macOS)
extension Touchpoints {
    public static func system(hatsVersion: String) -> Touchpoints {
        Touchpoints(
            processes: DarwinProcessTable(),
            control: WorkspaceAppControl(),
            credentials: KeychainCredentialProbe(),
            dock: SystemDockPreferences(),
            discarder: .trash,
            registrar: .launchServices,
            folderOpener: WorkspaceFolderOpener(),
            urlSchemeHandler: Doctor.systemURLSchemeHandler,
            appSearch: .system,
            applicationsDir: URL(filePath: "/Applications", directoryHint: .isDirectory),
            releaseFeed: GitHubReleaseFeed(currentVersion: hatsVersion)
        )
    }
}
#endif
