import Foundation

struct UninstallSearchRoot: Hashable, Sendable {
    enum Base: Hashable, Sendable {
        case userLibrary
        case systemLibrary
    }

    enum MatchStyle: String, Hashable, Sendable, CaseIterable {
        case bundleID
        case groupContainer
        case applicationGroup
        case displayName
        case executableArtifact
    }

    let base: Base
    /// Relative to `base`, never empty.
    let relativePath: String
    let styles: Set<MatchStyle>
    let maxDepth: Int

    init(
        base: Base, relativePath: String, styles: Set<MatchStyle>, maxDepth: Int = 1
    ) {
        self.base = base
        self.relativePath = relativePath
        self.styles = styles
        self.maxDepth = maxDepth
    }

    func path(home: String) -> String {
        switch base {
        case .userLibrary: return home + "/Library/" + relativePath
        case .systemLibrary: return "/Library/" + relativePath
        }
    }

    static let all: [UninstallSearchRoot] = [
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Application Support",
            styles: [.bundleID, .displayName], maxDepth: 2),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Caches", styles: [.bundleID, .displayName],
            maxDepth: 2),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Caches/Metadata",
            styles: [.bundleID, .displayName], maxDepth: 2),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Logs", styles: [.bundleID, .displayName],
            maxDepth: 2),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Logs/DiagnosticReports",
            styles: [.bundleID, .executableArtifact]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Logs/CrashReporter",
            styles: [.bundleID, .executableArtifact]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Containers", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Group Containers",
            styles: [.applicationGroup, .groupContainer]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Application Scripts",
            styles: [.bundleID, .applicationGroup, .groupContainer]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Preferences", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "SyncedPreferences", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Preferences/ByHost", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Saved Application State", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "HTTPStorages", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "WebKit", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Cookies", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Autosave Information", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "LaunchAgents", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Internet Plug-Ins", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "QuickLook", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Services", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "PreferencePanes", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Screen Savers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Spotlight", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Automator", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Input Methods", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Contextual Menu Items",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Mail/Bundles", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "QuickTime", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Widgets", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "ColorPickers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "PDF Services", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Keyboard Layouts",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "ScriptingAdditions",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Metadata", styles: [.bundleID], maxDepth: 2),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/HAL", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/Components",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/VST",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/VST3",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "CoreMediaIO/Plug-Ins/DAL",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Application Support",
            styles: [.bundleID, .displayName], maxDepth: 2),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Caches", styles: [.bundleID], maxDepth: 2),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Caches/Metadata", styles: [.bundleID],
            maxDepth: 2),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Logs", styles: [.bundleID], maxDepth: 2),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Logs/DiagnosticReports",
            styles: [.bundleID, .executableArtifact]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Logs/CrashReporter",
            styles: [.bundleID, .executableArtifact]),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "Preferences", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "SyncedPreferences", styles: [.bundleID]),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "LaunchAgents", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "LaunchDaemons", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "PrivilegedHelperTools", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Internet Plug-Ins",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "QuickLook", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Contextual Menu Items",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Mail/Bundles",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "QuickTime", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Widgets", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "ColorPickers",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "PDF Services",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Keyboard Layouts",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "ScriptingAdditions",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Components",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Metadata", styles: [.bundleID], maxDepth: 2),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "PreferencePanes", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Screen Savers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/HAL",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/Components",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/VST",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/VST3",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "CoreMediaIO/Plug-Ins/DAL",
            styles: [.bundleID, .displayName])
    ]

    static let binDirectories: [String] = [
        "/usr/local/bin", "/opt/homebrew/bin", "~/.local/bin", "~/bin"
    ]
}
