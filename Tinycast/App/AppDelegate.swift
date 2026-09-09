import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if UI_TESTING
        let bundleID = Bundle.main.bundleIdentifier!
        precondition(bundleID == "com.tinycast.app.uitesting")
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        #endif
        AppCore.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The Hyper Key's HID-level caps remap outlives the process; give the key back.
        AppCore.shared.prepareForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        #if !UI_TESTING
        AppCore.shared.paletteCoordinator.handleReopen()
        #endif
        return true
    }
}
