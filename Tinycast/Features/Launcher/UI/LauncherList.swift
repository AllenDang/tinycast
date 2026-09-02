import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selectedID: AppEntry.ID?
    let favoriteCount: Int
    let showSections: Bool
    let scroll: ScrollIntent
    var calc: CalcResult?
    var calcSelected = false
    var onActivateCalc: () -> Void = {}
    var onCalcActions: () -> Void = {}
    var aiIntent: AICommandMatch?
    var aiIntentSelected = false
    var onActivateAI: () -> Void = {}
    var aiPending: AICommand?
    var aiPendingSelected = false
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    var funcSuggestions: [CalcParser.FunctionSuggestion] = []
    var funcSuggestionSelectedIndex: Int = -1
    var onSelectFuncSuggestion: (CalcParser.FunctionSuggestion) -> Void = { _ in }
    @Environment(RunningAppsMonitor.self) private var runningApps
    @Environment(HotKeyBindings.self) private var hotKeys
    @Environment(AppSettings.self) private var settings

    private nonisolated static let calcRowID = "calc-card"
    private nonisolated static let aiRowID = "ai-command-card"
    private nonisolated static let aiPendingRowID = "ai-command-hint"

    private enum Row: Identifiable {
        case header(String)
        case calc(CalcResult)
        case aiCommand(AICommandMatch)
        case aiPendingCommand(AICommand)
        // The index addresses the original suggestions array.
        case funcSuggestion(CalcParser.FunctionSuggestion, Int)
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
            (AppEntry.Kind.application.descriptor.sectionTitle, .application),
            (AppEntry.Kind.systemSettings.descriptor.sectionTitle, .systemSettings),
            (AppEntry.Kind.quicklink.descriptor.sectionTitle, .quicklink),
            (AppEntry.Kind.snippet.descriptor.sectionTitle, .snippet),
            (AppEntry.Kind.systemAction.descriptor.sectionTitle, .systemAction),
            (AppEntry.Kind.windowCommand.descriptor.sectionTitle, .windowCommand),
            (AppEntry.Kind.customCommand.descriptor.sectionTitle, .customCommand),
            (AppEntry.Kind.command.descriptor.sectionTitle, .command)
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
                                        shortcutCaps: app.hotKeyAction.flatMap {
                                            hotKeys.binding(for: $0)?.keycaps(
                                                hyperKey: settings.hyperKey,
                                                includesShift: settings.hyperKeyIncludesShift,
                                                replacesGlyph: settings.hyperKeyReplacesGlyph)
                                        }
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

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let running: Bool
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
