import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    // Same UserDefaults key the `App` binds its `MenuBarExtra(isInserted:)` to — toggling here
    // updates the menu-bar icon live, with no shared observable object between them.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    var body: some View {
        SettingsPane(
            title: "General",
            subtitle: "Global shortcuts and startup behaviour."
        ) {
            SettingsCard(header: "Global Shortcuts") {
                SettingsRow(
                    title: "App Launcher",
                    subtitle: "Summon the fuzzy app launcher.",
                    systemImage: "magnifyingglass",
                    tint: .blue
                ) {
                    KeyboardShortcuts.Recorder("", name: .togglePalette)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Clipboard History",
                    subtitle: "Open the clipboard history browser.",
                    systemImage: "doc.on.clipboard",
                    tint: .orange
                ) {
                    KeyboardShortcuts.Recorder("", name: .toggleClipboard)
                }
            }

            SettingsCard(header: "General") {
                SettingsRow(
                    title: "Launch at login",
                    subtitle: "Start Tinycast automatically when you log in.",
                    systemImage: "power",
                    tint: .green
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Show in menu bar",
                    subtitle:
                        "Keep the Tinycast icon in the menu bar. Hotkeys still work when hidden.",
                    systemImage: "menubar.arrow.up.rectangle",
                    tint: .gray
                ) {
                    Toggle("", isOn: $showInMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }
}
