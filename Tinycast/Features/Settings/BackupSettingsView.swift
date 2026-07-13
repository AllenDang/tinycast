import AppKit
import SwiftUI

struct BackupSettingsView: View {
    @State private var raycastFile: URL?
    @State private var passphrase = ""
    @State private var importing = false
    @State private var status: Status?

    private enum Status {
        case success(String)
        case failure(String)
    }

    var body: some View {
        SettingsPane(
            title: "Backup",
            subtitle: "Export your settings, restore a backup, or import from Raycast."
        ) {
            SettingsCard(header: "Tinycast") {
                SettingsRow(
                    title: "Export Settings",
                    subtitle: "Save your shortcuts, favorites, and preferences to a JSON file.",
                    systemImage: "square.and.arrow.up",
                    tint: .blue
                ) {
                    Button("Export…") { BackupActions.exportSettings() }
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Import Settings",
                    subtitle: "Restore from a Tinycast backup. Only values in the file are changed.",
                    systemImage: "square.and.arrow.down",
                    tint: .green
                ) {
                    Button("Import…") { BackupActions.importSettings() }
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Import from Raycast") {
                SettingsRow(
                    title: "Raycast Export",
                    subtitle: raycastFile?.lastPathComponent
                        ?? "Choose a .rayconfig file exported from Raycast.",
                    systemImage: "doc.badge.gearshape",
                    tint: .orange
                ) {
                    Button("Choose…") { chooseRaycastFile() }
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Passphrase",
                    subtitle: "The password you set when exporting from Raycast.",
                    systemImage: "key",
                    tint: .gray
                ) {
                    SecureField("Passphrase", text: $passphrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(runRaycastImport)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Import",
                    subtitle:
                        "Maps the palette hotkey, launch-at-login, emoji skin tone, and clipboard history into Tinycast.",
                    systemImage: "arrow.down.circle",
                    tint: .indigo
                ) {
                    if importing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Import") { runRaycastImport() }
                            .controlSize(.small)
                            .disabled(raycastFile == nil || passphrase.isEmpty)
                    }
                }
                if let status {
                    SettingsDivider()
                    statusRow(status)
                }
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ status: Status) -> some View {
        switch status {
        case .success(let message):
            SettingsRow(title: message, systemImage: "checkmark.circle.fill", tint: .green) {
                EmptyView()
            }
        case .failure(let message):
            SettingsRow(title: message, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            {
                EmptyView()
            }
        }
    }

    private func chooseRaycastFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            raycastFile = panel.url
            status = nil
        }
    }

    private func runRaycastImport() {
        guard let file = raycastFile, !passphrase.isEmpty, !importing else { return }
        importing = true
        status = nil
        Task {
            defer { importing = false }
            do {
                let outcome = try await BackupActions.importRaycast(file: file, passphrase: passphrase)
                var message = BackupActions.summaryText(outcome.summary)
                if outcome.clipboardImported > 0 {
                    message += " Imported \(outcome.clipboardImported) clipboard entries."
                }
                if outcome.missingImages > 0 {
                    message += " \(outcome.missingImages) images were unavailable and skipped."
                }
                status = .success(message)
                passphrase = ""
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}
