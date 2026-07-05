import SwiftUI

@main
struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` is the idiomatic driver for scene state persisted in UserDefaults. Unlike
    // observing a shared `@Published` object from the `App`, it only republishes when the value
    // actually changes — no scene ⇄ binding feedback loop. The Settings toggle writes the same key.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    // Channel-aware: "Tinycast", "Tinycast Alpha", or "Tinycast Beta".
    private let appName = Bundle.main.appDisplayName

    var body: some Scene {
        MenuBarExtra(
            appName, systemImage: "macwindow", isInserted: $showInMenuBar
        ) {
            Button("Open \(appName)") { AppCore.shared.showPalette(mode: .launcher) }
            Button("Clipboard History") { AppCore.shared.showPalette(mode: .clipboard) }
            Divider()
            Button("Settings...") { AppCore.shared.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit \(appName)") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
