import AppKit
import UniformTypeIdentifiers

/// Stateless file panels, Raycast detection and summary formatting shared by backup UI flows.
@MainActor
enum BackupActions {
    /// The JSON save panel, shared with the quicklinks archive.
    static func chooseSaveLocation(named base: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(base)-\(dateStamp()).json"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func chooseJSONFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Every Raycast channel (stable, beta, alpha, internal) shares this bundle-id prefix.
    static let raycastBundleIDPrefix = "com.raycast"

    static func isRaycastBundleID(_ id: String) -> Bool { id.hasPrefix(raycastBundleIDPrefix) }

    static func quitRaycast() {
        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier.map(isRaycastBundleID) == true
            && app.activationPolicy != .prohibited {
            app.terminate()
        }
    }

    static func pickRaycastFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func detectRaycastFormat(of file: URL) -> RaycastFormat? {
        guard let raw = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return try? RaycastFormat.detect(raw)
    }

    static func summaryText(_ summary: SettingsBackup.ApplySummary) -> String {
        appliedText(summary) ?? nothingImportedText
    }

    static let nothingImportedText = "Nothing to import from this file."

    static func appliedText(_ summary: SettingsBackup.ApplySummary) -> String? {
        var parts: [String] = []
        if summary.settingsFields > 0 { parts.append("\(summary.settingsFields) settings") }
        if summary.hotkeys > 0 { parts.append("\(summary.hotkeys) shortcuts") }
        if summary.favorites > 0 { parts.append("\(summary.favorites) favorites") }
        if summary.hiddenItems > 0 { parts.append("\(summary.hiddenItems) hidden items") }
        if summary.customCommands > 0 {
            parts.append("\(summary.customCommands) custom commands")
        }
        if summary.quicklinks > 0 { parts.append("\(summary.quicklinks) quicklinks") }
        guard !parts.isEmpty else { return nil }
        return "Applied " + parts.joined(separator: ", ") + "."
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
