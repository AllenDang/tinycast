import SwiftUI

extension Notification.Name {
    static let tinycastShowSettings = Notification.Name("TinycastShowSettings")
}

private enum SettingsTab {
    case general, appHotkeys
}

struct SettingsRootView: View {
    @State private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AppHotkeysSettingsView()
                .tabItem { Label("App Hotkeys", systemImage: "keyboard") }
                .tag(SettingsTab.appHotkeys)
        }
        .frame(width: 500, height: 440)
        .onReceive(NotificationCenter.default.publisher(for: .tinycastShowSettings)) { _ in
            tab = .general
        }
    }
}
