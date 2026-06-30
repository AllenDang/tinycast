import SwiftUI

extension Notification.Name {
    static let tinycastShowSettings = Notification.Name("TinycastShowSettings")
}

private enum SettingsTab: Hashable {
    case general, appHotkeys
}

struct SettingsRootView: View {
    @State private var tab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("General").tag(SettingsTab.general)
                Text("App Hotkeys").tag(SettingsTab.appHotkeys)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .padding(.vertical, 10)

            Divider()

            // A plain conditional swap — not a `TabView`. macOS's TabView is backed by `NSTabView`,
            // which re-hosts each tab's view on selection; that re-hosting is the visible flicker and
            // it also tears down the hotkey `Recorder`'s window membership mid-interaction (so the
            // first recording attempt fails). Switching content this way keeps each pane's hosting
            // view stable, fixing both.
            Group {
                switch tab {
                case .general: GeneralSettingsView()
                case .appHotkeys: AppHotkeysSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 440)
        .onReceive(NotificationCenter.default.publisher(for: .tinycastShowSettings)) { _ in
            tab = .general
        }
    }
}
