import AppKit
import SwiftUI

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case calculatorHistory
    case emoji
    case uninstall
    case quicklinks
    /// Collects a quicklink's `{argument}` values before it opens; the pending request lives on
    /// `AppCore.quicklinkArguments`, the way `.uninstall`'s target lives on `UninstallSession`.
    case quicklinkArguments
    /// The loading/answer screen for a committed `AICommandCard`; the pending request lives on
    /// `AppCore.aiCommandSession`.
    case aiCommand

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .uninstall: return "trash"
        case .quicklinks, .quicklinkArguments: return Quicklink.sfSymbol
        case .aiCommand: return AICommand.sfSymbol
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .calculatorHistory: return "Do math, convert units, or search your past calculations…"
        case .emoji: return "Search emoji and symbols…"
        case .uninstall: return "Filter files and folders by name…"
        case .quicklinks: return "Search quicklinks…"
        // Replaced by the pending argument's name; only reached if the session vanished mid-render.
        case .quicklinkArguments: return "Enter a value…"
        case .aiCommand: return "Press ↵ to copy the result…"
        }
    }
}

/// The app a paste will land in, resolved once per palette show so the footer pill and menu rows can name it without re-reading `NSWorkspace` on every render.
struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { "Paste to \(name)" }
}

/// View-model shared between the panel's SwiftUI tree and the coordinator.
@MainActor
@Observable
final class PaletteViewModel {
    var mode: PaletteMode = .launcher
    var query: String = ""
    var selection: Int = 0
    /// Changes every time the palette is shown so the search field can re-focus.
    var focusToken = UUID()
    /// Changes only when `prepare` resets the palette, so the lists snap their scroll to the top even when query/mode were already at their defaults (`focusToken` can't serve: it bumps on every reopen, which must preserve a within-timeout scroll).
    var resetToken = UUID()
    /// Changes when an action reorders the list under the selection (pinning a clip lifts it into the Pinned section), so the list scrolls the highlight back into view.
    var followToken = UUID()
    /// Set by the compact bar's "…" overflow to expand into the full launcher without a query; cleared on every `prepare`.
    var forceExpanded = false
    /// The app a paste would land in, mirrored from `PaletteWindowController.previousApp` on every show. Deliberately *not* cleared by `prepare` — pop-to-root resets the screen, not the paste target.
    var pasteTarget: PasteTarget?
    /// Gates the mouse-hover highlight: true only while the pointer is physically moving (armed on `.mouseMoved`, disarmed on any `.keyDown` in `PalettePanel.sendEvent`). Untracked — read at hover time, never drives a re-render.
    @ObservationIgnored var hoverHighlightArmed = false
    /// True whenever the search field should read as inert without losing focus: a footer popover menu (⌘K Actions or the app menu) is open, or the palette is showing `.aiCommand` — that screen's request already fired with the query it matched against, so further edits would do nothing. `PalettePanel.sendEvent` swallows text-editing keystrokes the field editor would otherwise consume while this is true (matches Raycast). Untracked — read at event time, mirrored from the view's own state.
    @ObservationIgnored var searchFieldFrozen = false { didSet { onSearchFieldFrozenChanged?(searchFieldFrozen) } }
    /// Fired when `searchFieldFrozen` flips so `PalettePanel` can hide/show the search field's caret while it keeps first-responder status (no focus swap, so the placeholder never reflows).
    @ObservationIgnored var onSearchFieldFrozenChanged: ((Bool) -> Void)?

    /// True while the field editor holds an uncommitted IME candidate (Pinyin, Cangjie, romaji…).
    /// `query` never sees marked text — SwiftUI's own `TextField` binding doesn't update until a
    /// candidate commits — so anything gated on `query.isEmpty` needs this alongside it if "there's
    /// visible content in the field" is what it actually means. Mirrored from `PalettePanel.sendEvent`,
    /// which is the one place that can read the live field editor's `hasMarkedText()` after every keystroke.
    var isComposing = false
    /// Cached AI provider state — checked once per palette open, not on every keystroke, because `AIProviderStore.isConfigured` reads the keychain.
    var aiConfigured = false

    func prepare(mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        forceExpanded = false
        hoverHighlightArmed = false
        searchFieldFrozen = false
        isComposing = false
        focusToken = UUID()
        resetToken = UUID()
    }
}
