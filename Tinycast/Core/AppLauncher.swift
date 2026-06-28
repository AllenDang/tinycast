import AppKit
import os

enum AppLauncher {
    private static let log = Logger(subsystem: "com.tinycast.app", category: "launcher")

    @MainActor
    static func launch(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Toggle behaviour: focus the app if it is not frontmost, hide it if it is,
    /// launch it if it isn't running.
    @MainActor
    static func toggle(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let app = running.first {
            if app.isActive {
                log.debug("toggle hide \(bundleID, privacy: .public)")
                app.hide()
            } else {
                log.debug("toggle activate \(bundleID, privacy: .public)")
                app.unhide()
                app.activate()
            }
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            log.debug("toggle launch \(bundleID, privacy: .public)")
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            log.debug("toggle: no app for \(bundleID, privacy: .public)")
        }
    }
}
