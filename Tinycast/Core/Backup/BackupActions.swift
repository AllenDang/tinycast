import AppKit
import UniformTypeIdentifiers

/// User-facing entry points for the backup flows, shared between the Settings pane and the palette commands. The Raycast decrypt runs off the main actor (scrypt is CPU-heavy); everything else is quick.
@MainActor
enum BackupActions {
    struct RaycastOutcome {
        var summary: SettingsBackup.ApplySummary
        var clipboardImported: Int
        var missingImages: Int
    }

    // MARK: - Tinycast native (self-contained: own file panels + alerts)

    static func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Tinycast-Settings-\(dateStamp()).json"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.gather().encoded().write(to: url, options: .atomic)
        } catch {
            present(title: "Export Failed", message: error.localizedDescription, style: .warning)
        }
    }

    static func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let backup = try SettingsBackup(json: try Data(contentsOf: url))
            present(
                title: "Settings Imported", message: summaryText(backup.apply()), style: .informational
            )
        } catch {
            present(title: "Import Failed", message: error.localizedDescription, style: .warning)
        }
    }

    // MARK: - Raycast (the pane owns the passphrase field + inline status)

    static func importRaycast(file: URL, passphrase: String) async throws -> RaycastOutcome {
        // scrypt + AES-GCM + gunzip: keep off the main actor so the window stays responsive.
        let decrypted = try await Task.detached(priority: .userInitiated) {
            try RaycastImport.decrypt(file: file, passphrase: passphrase)
        }.value
        let result = try RaycastImport.parse(decrypted)
        let summary = result.backup.apply()
        let imported = AppCore.shared.clipboardStore.importEntries(result.clipboard)
        return RaycastOutcome(
            summary: summary, clipboardImported: imported, missingImages: result.missingImages)
    }

    // MARK: - Helpers

    static func summaryText(_ s: SettingsBackup.ApplySummary) -> String {
        var parts: [String] = []
        if s.settingsFields > 0 { parts.append("\(s.settingsFields) settings") }
        if s.hotkeys > 0 { parts.append("\(s.hotkeys) shortcuts") }
        if s.favorites > 0 { parts.append("\(s.favorites) favorites") }
        if s.hiddenItems > 0 { parts.append("\(s.hiddenItems) hidden items") }
        return parts.isEmpty ? "Nothing to import from this file." : "Applied " + parts.joined(separator: ", ") + "."
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func present(title: String, message: String, style: NSAlert.Style) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
}
