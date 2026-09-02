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

    @MainActor
    static func showInfoInFinder(_ url: URL) -> Bool {
        let source = """
            tell application "Finder"
                activate
                open information window of (POSIX file "\(url.path)" as alias)
            end tell
            """
        guard let script = NSAppleScript(source: source) else { return false }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }

    /// Opens System Settings at the pane backed by the given extension bundle ID.
    @MainActor
    static func openSettingsPane(bundleID: String) {
        guard let url = URL(string: "x-apple.systempreferences:" + bundleID) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Focus the app if it isn't frontmost, hide it if it is, launch it if it isn't running.
    @MainActor
    static func toggle(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first
        if let running, running.isActive {
            running.hide()
            return
        }
        if let url = running?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let running {
            // Running app whose bundle URL can't be resolved (moved or deleted since launch).
            running.unhide()
            running.activate()
        }
    }

    @MainActor
    @discardableResult
    static func quit(bundleID: String) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in running { app.terminate() }
        return !running.isEmpty
    }

    private static let quitAllExclusions: Set<String> = ["com.apple.finder"]

    @MainActor
    static func quitAllTargets() -> [NSRunningApplication] {
        let ownPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.processIdentifier != ownPID
                && !quitAllExclusions.contains(app.bundleIdentifier ?? "")
        }
    }
}
