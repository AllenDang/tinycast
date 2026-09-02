import AppKit

struct KindDescriptor {
    let label: String
    let sectionTitle: String
    let openVerb: String
    let canRevealInFinder: Bool
    let isSymbolIcon: Bool
}

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case application
        case systemSettings
        case command
        case customCommand
        case snippet
        case systemAction
        case windowCommand
        case quicklink

        var descriptor: KindDescriptor {
            switch self {
            case .application:
                return KindDescriptor(
                    label: "Application", sectionTitle: "Applications",
                    openVerb: "Open Application", canRevealInFinder: true, isSymbolIcon: false)
            case .systemSettings:
                return KindDescriptor(
                    label: "System Setting", sectionTitle: "System Settings",
                    openVerb: "Open System Setting", canRevealInFinder: true, isSymbolIcon: false)
            case .command:
                return KindDescriptor(
                    label: "Command", sectionTitle: "Commands", openVerb: "Run Command",
                    canRevealInFinder: false, isSymbolIcon: true)
            case .customCommand:
                return KindDescriptor(
                    label: "Custom Command", sectionTitle: "Custom Commands",
                    openVerb: "Run Custom Command", canRevealInFinder: false, isSymbolIcon: true)
            case .snippet:
                return KindDescriptor(
                    label: "Snippet", sectionTitle: "Snippets", openVerb: "Paste Snippet",
                    canRevealInFinder: true, isSymbolIcon: true)
            case .systemAction:
                return KindDescriptor(
                    label: "System Action", sectionTitle: "System Actions",
                    openVerb: "Run System Action", canRevealInFinder: false, isSymbolIcon: true)
            case .windowCommand:
                return KindDescriptor(
                    label: "Window Command", sectionTitle: "Window Management",
                    openVerb: "Move Window", canRevealInFinder: false, isSymbolIcon: true)
            case .quicklink:
                return KindDescriptor(
                    label: "Quicklink", sectionTitle: "Quicklinks", openVerb: "Open Quicklink",
                    canRevealInFinder: false, isSymbolIcon: true)
            }
        }
    }

    let id: String  // file path (or "command:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    var matchAliases: [String] = []
    var symbolName: String?
    /// Spotlight's `kMDItemAlternateNames`, ranked below the display name. Applications only.
    var alternateNames: [String] = []
    /// `CFBundleExecutable`, matched literally as a last resort. Applications only.
    var executableName: String?
    var normalizedSearchFields: SearchFieldsNormalized?

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    var searchFields: SearchFields {
        SearchFields(
            names: [name] + matchAliases, alternateNames: alternateNames,
            bundleID: bundleID, executableName: executableName)
    }

    var kindLabel: String { kind.descriptor.label }

    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .application:
            return bundleID.map { .app(bundleID: $0) }
        case .systemSettings:
            return bundleID.map { .settingsPane(bundleID: $0) }
        case .customCommand:
            return CustomCommand.id(fromEntryID: id).map { .customCommand(id: $0) }
        case .systemAction:
            return SystemActionCatalog.action(forEntryID: id).map { .systemAction(id: $0.id) }
        case .windowCommand:
            return WindowCommandCatalog.command(forEntryID: id).map { .windowCommand(id: $0.id) }
        case .quicklink:
            return Quicklink.id(fromEntryID: id).map { .quicklink(id: $0) }
        case .command, .snippet:
            return nil
        }
    }

    var canRevealInFinder: Bool { kind.descriptor.canRevealInFinder }

    /// Synthetic entries draw an SF Symbol tile; everything else uses its file icon.
    var isSymbolIcon: Bool { kind.descriptor.isSymbolIcon }

    var symbolIconName: String {
        if let symbolName { return symbolName }
        switch kind {
        case .quicklink: return Quicklink.sfSymbol
        case .snippet: return "text.quote"
        case .customCommand: return CustomCommand.sfSymbol
        case .command: return CommandCatalog.command(for: self)?.sfSymbol ?? "questionmark"
        case .systemAction: return SystemActionCatalog.action(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .windowCommand:
            return WindowCommandCatalog.command(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .application, .systemSettings: return "questionmark"
        }
    }

    var icon: NSImage {
        isSymbolIcon
            ? IconCache.symbolIcon(named: symbolIconName) : IconCache.icon(forFile: url.path)
    }
}
