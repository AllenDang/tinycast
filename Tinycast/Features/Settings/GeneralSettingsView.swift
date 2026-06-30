import SwiftUI
import KeyboardShortcuts

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Global Shortcuts") {
                KeyboardShortcuts.Recorder("App Launcher:", name: .togglePalette)
                KeyboardShortcuts.Recorder("Clipboard History:", name: .toggleClipboard)
            }

            Section("Clipboard") {
                Stepper(
                    "History size: \(settings.clipboardMaxItems) items",
                    value: $settings.clipboardMaxItems, in: 50...2000, step: 50
                )
                .onChange(of: settings.clipboardMaxItems) {
                    AppCore.shared.clipboardStore.maxItems = settings.clipboardMaxItems
                }
                Button("Clear Clipboard History") {
                    AppCore.shared.clipboardStore.clearAll()
                }
            }

            Section("Permissions") {
                LabeledContent("Accessibility (paste)") {
                    HStack(spacing: 8) {
                        Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                        Button("Open Settings…") { Permissions.openAccessibilitySettings() }
                    }
                }
                Text("Required so Tinycast can paste a clipboard item into the app you were using.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch Tinycast at login", isOn: $settings.launchAtLogin)
                    // Attached to a row (not the Form) so the configurator lands inside the
                    // Form's own scroll view, where `enclosingScrollView` can find it.
                    .thinOverlayScrollbar()
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        }
    }
}
