import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppHotkeysSettingsView()
                .tabItem { Label("App Hotkeys", systemImage: "keyboard") }
        }
        .frame(width: 500, height: 440)
    }
}
