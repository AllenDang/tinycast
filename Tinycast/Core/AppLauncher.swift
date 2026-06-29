import AppKit

enum AppLauncher {

    @MainActor
    static func launch(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @MainActor
    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Toggle behaviour: focus the app if it is not frontmost, hide it if it is,
    /// launch it if it isn't running.
    @MainActor
    static func toggle(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let app = running.first {
            if app.isActive {
                app.hide()
            } else {
                app.unhide()
                app.activate()
            }
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
