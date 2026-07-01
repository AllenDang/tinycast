import SwiftUI

struct ClipboardSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @State private var confirmingClear = false

    var body: some View {
        SettingsPane(
            title: "Clipboard",
            subtitle: "Control how much history Tinycast keeps."
        ) {
            SettingsCard(header: "History") {
                SettingsRow(
                    title: "Items to keep",
                    subtitle: "Older entries are dropped once the limit is reached.",
                    systemImage: "tray.full",
                    tint: .orange
                ) {
                    HStack(spacing: 8) {
                        Text("\(settings.clipboardMaxItems)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 42, alignment: .trailing)
                        Stepper(
                            "",
                            value: $settings.clipboardMaxItems, in: 50...2000, step: 50
                        )
                        .labelsHidden()
                        .onChange(of: settings.clipboardMaxItems) {
                            AppCore.shared.clipboardStore.maxItems = settings.clipboardMaxItems
                        }
                    }
                }
            }

            SettingsCard(header: "Danger Zone") {
                SettingsRow(
                    title: "Clear history",
                    subtitle: "Permanently remove every saved clip and image.",
                    systemImage: "trash",
                    tint: .red
                ) {
                    Button("Clear…", role: .destructive) { confirmingClear = true }
                        .controlSize(.regular)
                }
            }
        }
        .confirmationDialog(
            "Clear clipboard history?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                AppCore.shared.clipboardStore.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}
