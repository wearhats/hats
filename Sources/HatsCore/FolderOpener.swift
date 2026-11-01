import Foundation

#if os(macOS)
import AppKit
#endif

public protocol FolderOpener: Sendable {
    /// `false` if the system refused to show `folder`.
    func open(_ folder: URL) -> Bool
}

#if os(macOS)
public struct WorkspaceFolderOpener: FolderOpener {
    public init() {}

    public func open(_ folder: URL) -> Bool {
        NSWorkspace.shared.open(folder)
    }
}
#endif

/// Creates the launchers folder if it is missing, then shows it.
public func revealLaunchers(layout: Layout, opener: any FolderOpener) throws(HatsError) {
    do {
        try FileManager.default.createDirectory(at: layout.launcherDir, withIntermediateDirectories: true)
    } catch {
        throw HatsError(.io, "cannot create \(layout.launcherDir.plainPath): \(error.localizedDescription)")
    }
    _ = opener.open(layout.launcherDir)
}
