import SwiftUI

@main
struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Tinycast", systemImage: "command.square") {
            Button("Open Tinycast") { AppCore.shared.showPalette(mode: .launcher) }
            Button("Clipboard History") { AppCore.shared.showPalette(mode: .clipboard) }
            Divider()
            Button("Settings…") { AppCore.shared.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Tinycast") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
