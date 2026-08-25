import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selectedID: AppEntry.ID?
    let favoriteCount: Int
    let showSections: Bool
    /// Changes only when the list should scroll (keyboard nav / reset), so mouse selection never yanks the scroll position.
    let scroll: ScrollIntent
    /// Inline calculator answer; occupies flat selection index 0 when present (requires a non-empty query, so it never coexists with the sectioned view).
    var calc: CalcResult?
    var calcSelected = false
    var onActivateCalc: () -> Void = {}
    var onCalcActions: () -> Void = {}
    /// The AI command intent card; mutually exclusive with `calc` (the caller never sets both), and
    /// occupies the same flat selection index 0 slot when present.
    var aiIntent: AICommandMatch?
    var aiIntentSelected = false
    var onActivateAI: () -> Void = {}
    /// The AI command hint — keyword recognized, no argument text yet — mutually exclusive with both
    /// `calc` and `aiIntent`, same slot. Never actionable, so there's no `onActivate` for it.
    var aiPending: AICommand?
    var aiPendingSelected = false
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    /// Function name autocomplete suggestions (shown after the calculator card, before app results).
    var funcSuggestions: [CalcParser.FunctionSuggestion] = []
    var funcSuggestionSelectedIndex: Int = -1
    var onSelectFuncSuggestion: (CalcParser.FunctionSuggestion) -> Void = { _ in }
    @Environment(RunningAppsMonitor.self) private var runningApps
    @Environment(HotKeyManager.self) private var hotKeys

    private nonisolated static let calcRowID = "calc-card"
    private nonisolated static let aiRowID = "ai-command-card"
    private nonisolated static let aiPendingRowID = "ai-command-hint"

    private enum Row: Identifiable {
        case header(String)
        case calc(CalcResult)
        case aiCommand(AICommandMatch)
        case aiPendingCommand(AICommand)
        case funcSuggestion(CalcParser.FunctionSuggestion, Int)  // suggestion + index in suggestions array
        case app(AppEntry)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .calc: return LauncherList.calcRowID
            case .aiCommand: return LauncherList.aiRowID
            case .aiPendingCommand: return LauncherList.aiPendingRowID
            case .funcSuggestion(let f, _): return "func-\(f.name)"
            case .app(let app): return app.id
            }
        }
    }

    /// Scroll target for the current selection.
    private var selectedRowID: String? {
        if calcSelected { return Self.calcRowID }
        if aiIntentSelected { return Self.aiRowID }
        if aiPendingSelected { return Self.aiPendingRowID }
        return selectedID
    }

    /// Whether the selection sits on flat index 0 — the calc card, AI command card or AI hint when present, else the first result.
    private var firstRowSelected: Bool {
        if calc != nil { return calcSelected }
        if aiIntent != nil { return aiIntentSelected }
        if aiPending != nil { return aiPendingSelected }
        return selectedID != nil && selectedID == results.first?.id
    }

    /// Cached rows so arrow-key nav doesn't re-map the same results array every render.

    private struct RowsKey: Equatable {
        let results: [AppEntry]
        let favoriteCount: Int
        let showSections: Bool
        let funcSuggestions: [CalcParser.FunctionSuggestion]
        let hasCalc: Bool
        let hasAIIntent: Bool
        let hasAIPending: Bool
    }

    @State private var rowsMemo = Memo<RowsKey, [Row]>()

    private func computeRows() -> [Row] {
        let key = RowsKey(
            results: results, favoriteCount: favoriteCount, showSections: showSections,
            funcSuggestions: funcSuggestions,
            hasCalc: calc != nil, hasAIIntent: aiIntent != nil, hasAIPending: aiPending != nil)
        return rowsMemo.value(for: key) { computeRowsUncached() }
    }

    private func computeRowsUncached() -> [Row] {
        var calcRows: [Row] = []
        if let calc {
            calcRows = [.header("Calculator"), .calc(calc)]
        } else if let aiIntent {
            calcRows = [.header(aiIntent.command.name), .aiCommand(aiIntent)]
        } else if let aiPending {
            calcRows = [.header(aiPending.name), .aiPendingCommand(aiPending)]
        }
        guard showSections else {
            var rows = calcRows
            if !funcSuggestions.isEmpty {
                rows.append(.header("Functions"))
                rows.append(contentsOf: funcSuggestions.enumerated().map { .funcSuggestion($0.element, $0.offset) })
            }
            guard !results.isEmpty else { return rows }
            return rows + [.header("Results")] + results.map(Row.app)
        }
        var rows: [Row] = calcRows
        if !funcSuggestions.isEmpty {
            rows.append(.header("Functions"))
            rows.append(contentsOf: funcSuggestions.enumerated().map { .funcSuggestion($0.element, $0.offset) })
        }
        let favorites = results.prefix(favoriteCount)
        let rest = results.dropFirst(favoriteCount)
        // Single pass: bucket by kind instead of 9 separate filter passes. Section order is fixed.
        var groups: [AppEntry.Kind: [AppEntry]] = [:]
        for entry in rest {
            groups[entry.kind, default: []].append(entry)
        }
        let sectionOrder: [(String, AppEntry.Kind)] = [
            ("Applications", .application),
            ("System Settings", .systemSettings),
            ("Quicklinks", .quicklink),
            ("Snippets", .snippet),
            ("System Actions", .systemAction),
            ("Window Management", .windowCommand),
            ("Custom Commands", .customCommand),
            ("Commands", .command)
        ]
        if !favorites.isEmpty {
            rows.append(.header("Favorites"))
            rows.append(contentsOf: favorites.map(Row.app))
        }
        for (title, kind) in sectionOrder {
            guard let group = groups[kind], !group.isEmpty else { continue }
            rows.append(.header(title))
            rows.append(contentsOf: group.map(Row.app))
        }
        return rows
    }

    var body: some View {
        let rows = computeRows()
        return Group {
            if results.isEmpty && calc == nil && aiIntent == nil && aiPending == nil && funcSuggestions.isEmpty {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                switch row {
                                case .header(let title):
                                    SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                                case .calc(let result):
                                    CalculatorCard(result: result, selected: calcSelected)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateCalc)
                                        .onRightClick(perform: onCalcActions)
                                        .padding(.bottom, Theme.Spacing.xs)
                                case .aiCommand(let match):
                                    AICommandCard(match: match, selected: aiIntentSelected)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateAI)
                                        .padding(.bottom, Theme.Spacing.xs)
                                case .aiPendingCommand(let command):
                                    AICommandHintCard(command: command, selected: aiPendingSelected)
                                        .padding(.bottom, Theme.Spacing.xs)
                                case .funcSuggestion(let fn, let idx):
                                    FuncSuggestionRow(suggestion: fn, selected: idx == funcSuggestionSelectedIndex)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onSelectFuncSuggestion(fn) }
                                        .padding(.bottom, Theme.Spacing.xs)
                                case .app(let app):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedID,
                                        running: runningApps.isRunning(app),
                                        shortcutCaps: app.hotKeyAction.flatMap { hotKeys.binding(for: $0)?.keycaps }
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { onActivate(app) }
                                    .onRightClick { onActions(app) }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.xs)
                        .padding(.bottom, Theme.Spacing.md)
                        .hideNativeScrollers()
                        .scrollOriginAnchor()
                    }
                    .edgeDissolve()
                    .thinScrollbar()
                    .onChange(of: scroll) { _, scroll in
                        switch scroll.kind {
                        case .top:
                            proxy.scrollToOrigin()
                        case .follow:
                            // On the first row, snap to the origin so its section header shows too — a nil anchor won't, since the row is already visible.
                            if firstRowSelected {
                                proxy.scrollToOrigin()
                            } else if let selectedRowID {
                                proxy.reveal(selectedRowID)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Section label above a group of rows, shared by every palette list so they use one identical header + row layout.
struct SectionHeader: View {
    let title: String
    /// The list's first header hugs the top; every later header gets `sectionSpacing` above it, which reads as bottom padding on the section that just ended.
    var isFirst = false
    var body: some View {
        Text(title)
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, isFirst ? Theme.Spacing.xs : Theme.Spacing.sectionSpacing)
            .padding(.bottom, Theme.Spacing.sectionHeaderBottom)
    }
}

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let running: Bool
    /// Keycaps for this entry's hotkey, or `nil` if none is bound. Pre-computed by the parent so
    /// `AppRow` doesn't need its own `@Environment(HotKeyManager.self)` — that would re-register
    /// observation tracking on every visible row every render during arrow-key nav.
    let shortcutCaps: [String]?
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            AppIconView(app: app)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)
                            .offset(y: 3)
                    }
                }
            Text(app.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            if let caps = shortcutCaps {
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            Text(app.kindLabel)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

/// Row icon that decodes off the main thread (mirrors `ImageThumbnail`), so surfacing new apps while typing never rasterizes on-main during render. Warm icons seed synchronously so there's no placeholder flash on re-open.
struct AppIconView: View {
    let app: AppEntry
    @State private var image: NSImage?

    init(app: AppEntry) {
        self.app = app
        _image = State(
            initialValue: app.isSymbolIcon
                ? IconCache.cachedSymbol(named: app.symbolIconName)
                : IconCache.cached(forFile: app.url.path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .task(id: app.id) {
            guard image == nil else { return }
            image =
                app.isSymbolIcon
                ? await IconCache.loadSymbolAsync(named: app.symbolIconName)
                : await IconCache.loadAsync(forFile: app.url.path)
        }
    }
}

/// Actions menu content for a launcher app, shown bottom-right on right-click or from the Actions pill.
@MainActor
enum AppActionsMenu {
    static func content(
        app: AppEntry, searchQuery: String, core: AppCore, favorites: FavoritesStore,
        running: Bool, onResetRanking: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: openTitle(app), systemImage: "list.bullet.rectangle", shortcut: "↵"
            ) { core.launch(app, searchQuery: searchQuery) }
        ]
        if favorites.isFavorite(app) {
            items.append(
                PopoverMenuItem(title: "Remove from Favorites", systemImage: "star.slash") {
                    favorites.toggle(app)
                })
        } else {
            items.append(
                PopoverMenuItem(title: "Add to Favorites", systemImage: "star") {
                    favorites.toggle(app)
                })
        }
        if core.launcherRanking.hasRanking(for: app.preferenceKey) {
            items.append(
                PopoverMenuItem(title: "Reset Ranking", systemImage: "arrow.counterclockwise") {
                    onResetRanking()
                })
        }
        if app.canRevealInFinder {
            items.append(
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵"
                ) {
                    core.showInFinder(app)
                })
        }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Quit Application", systemImage: "power", shortcut: "⌃⇧Q",
                    isDestructive: true
                ) {
                    core.quit(app)
                })
        }
        if app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall Application", systemImage: "trash", isDestructive: true
                ) {
                    core.beginUninstall(app)
                })
        }
        return PopoverMenuContent(header: app.name, items: items)
    }

    private static func openTitle(_ app: AppEntry) -> String {
        switch app.kind {
        case .application: return "Open Application"
        case .systemSettings: return "Open System Setting"
        case .command: return "Run Command"
        case .customCommand: return "Run Custom Command"
        case .snippet: return "Paste Snippet"
        case .systemAction: return "Run System Action"
        case .windowCommand: return "Move Window"
        case .quicklink: return "Open Quicklink"
        }
    }
}

/// Row for a function autocomplete suggestion: name, signature, and category.
private struct FuncSuggestionRow: View {
    let suggestion: CalcParser.FunctionSuggestion
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "function")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.rowIcon)
            Text(suggestion.name)
                .font(Theme.Typography.rowTitle.weight(.semibold))
            Text(suggestion.signature)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
            Spacer()
            Text(suggestion.category)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}
