import SwiftUI

/// The root search: cards and suggestions first, then favorites and launcher entry sections.
struct LauncherScreen: PaletteScreen {
    let appIndex: AppIndex
    let favorites: FavoritesStore
    let visibility: VisibilityStore
    let currencyRates: CurrencyRateStore
    let aiCommands: AICommandStore
    let aiProvider: AIProviderStore
    let launcher: LauncherCoordinator
    let aiCoordinator: AICommandCoordinator
    let calculatorCoordinator: CalculatorCoordinator
    let paletteCoordinator: PaletteCoordinator
    let vm: PaletteState
    let running: Bool
    let openActions: () -> Void

    enum Row: Identifiable {
        case calc(CalcResult)
        case aiReady(AICommandMatch)
        case aiPending(AICommand)
        case functionSuggestion(CalcParser.FunctionSuggestion, Int)
        case app(AppEntry)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .aiReady: return "ai-command-card"
            case .aiPending: return "ai-command-hint"
            case .functionSuggestion(let suggestion, let index):
                return "function:\(index):\(suggestion.name)"
            case .app(let app): return app.id
            }
        }
    }

    private var results: [AppEntry] {
        appIndex.orderedResults(query: vm.query, visibility: visibility, favorites: favorites)
    }

    private var calc: CalcResult? {
        CalcMemo.evaluate(vm.query, currency: currencyRates.source)
    }

    private var functionSuggestions: [CalcParser.FunctionSuggestion] {
        let trimmed = vm.query.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "=" || first == "＝" else { return [] }
        let expression = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        let lastToken = expression.split { " +-*/^×÷%!(),".contains($0) }.last.map(String.init) ?? ""
        guard lastToken.allSatisfy({ $0.isLetter || $0.isNumber }),
            lastToken.first?.isLetter == true
        else { return [] }
        return CalcParser.FunctionSuggestion.suggestions(matching: lastToken)
    }

    private var activeAICommands: [AICommand] {
        aiCommands.commands.filter { command in
            guard let providerID = command.providerID else { return false }
            return aiProvider.isProviderConfigured(providerID)
        }
    }

    private var aiReady: AICommandMatch? {
        guard calc == nil, vm.aiConfigured else { return nil }
        return AICommand.firstMatch(in: activeAICommands, query: vm.query)
    }

    private var aiPending: AICommand? {
        guard calc == nil, aiReady == nil, vm.aiConfigured else { return nil }
        return AICommand.pendingKeyword(in: activeAICommands, query: vm.query)
    }

    private enum LeadingValue {
        case calc(CalcResult)
        case aiReady(AICommandMatch)
        case aiPending(AICommand)

        var slot: LauncherLeadingSlot {
            switch self {
            case .calc: return .calculator
            case .aiReady: return .aiReady
            case .aiPending: return .aiPending
            }
        }
    }

    private var leadingValue: LeadingValue? {
        if let calc { return .calc(calc) }
        if let aiReady { return .aiReady(aiReady) }
        if let aiPending { return .aiPending(aiPending) }
        return nil
    }

    var rows: [Row] {
        let leading = leadingValue
        let functions = functionSuggestions
        let apps = results
        let layout = LauncherSelectableLayout(
            leading: leading?.slot, functionCount: functions.count, appCount: apps.count)
        return layout.slots.map { slot in
            switch slot {
            case .leading(.calculator):
                guard case .calc(let result) = leading else { preconditionFailure() }
                return .calc(result)
            case .leading(.aiReady):
                guard case .aiReady(let match) = leading else { preconditionFailure() }
                return .aiReady(match)
            case .leading(.aiPending):
                guard case .aiPending(let command) = leading else { preconditionFailure() }
                return .aiPending(command)
            case .function(let index):
                return .functionSuggestion(functions[index], index)
            case .app(let index):
                return .app(apps[index])
            }
        }
    }

    private var clampedSelection: Int {
        PaletteRowIndex(sectionCounts: [rows.count]).clamped(vm.selection)
    }

    var primaryActionTitle: String {
        switch row(at: clampedSelection) {
        case .calc: return "Copy Answer"
        case .aiReady(let match): return "Run \(match.command.name)"
        case .aiPending: return "Open Application"
        case .functionSuggestion: return "Insert Function"
        case .app(let app): return Self.pillTitle(app.kind)
        case nil: return "Open Application"
        }
    }

    private static func pillTitle(_ kind: AppEntry.Kind) -> String {
        switch kind {
        case .application:
            return kind.descriptor.openVerb
        case .systemSettings:
            return kind.descriptor.openVerb
        case .command:
            return kind.descriptor.openVerb
        case .customCommand:
            return kind.descriptor.openVerb
        // The footer historically labels these differently from their Actions-menu verbs.
        case .snippet:
            return "Open Application"
        case .systemAction:
            return kind.descriptor.openVerb
        case .windowCommand:
            return "Open Application"
        case .quicklink:
            return kind.descriptor.openVerb
        }
    }

    private func row(at selection: Int) -> Row? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func app(at selection: Int) -> AppEntry? {
        guard case .app(let app) = row(at: selection) else { return nil }
        return app
    }

    private func functionIndex(at selection: Int) -> Int {
        guard case .functionSuggestion(_, let index) = row(at: selection) else { return -1 }
        return index
    }

    func hasPrimaryAction(at selection: Int) -> Bool {
        switch row(at: selection) {
        case .calc(let result): return result.isActionable
        case .aiPending, nil: return false
        default: return true
        }
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable
                ? CalcActionsMenu.content(result: result, coordinator: calculatorCoordinator) : nil
        case .app(let app):
            return AppActionsMenu.content(
                app: app, searchQuery: vm.query, launcher: launcher, favorites: favorites,
                running: running,
                onResetRanking: {
                    launcher.resetRanking(for: app)
                    if let index = rows.firstIndex(where: { row in
                        if case .app(let candidate) = row { return candidate == app }
                        return false
                    }) { vm.selection = index }
                })
        default:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        case .calc(let result): calculatorCoordinator.copyResult(result)
        case .aiReady(let match): aiCoordinator.begin(match)
        case .aiPending: break
        case .functionSuggestion(let suggestion, _): insert(suggestion)
        case .app(let app): launcher.launch(app, searchQuery: vm.query)
        case nil: break
        }
    }

    func secondary(at selection: Int) -> Bool {
        guard let app = app(at: selection), app.canRevealInFinder else { return false }
        launcher.showInFinder(app)
        return true
    }

    func perform(_ command: PaletteCommand, at selection: Int) -> Bool {
        guard command == .quit, let app = app(at: selection), app.kind == .application,
            launcher.isRunning(app)
        else { return false }
        launcher.quit(app)
        return true
    }

    func isRunning(at selection: Int) -> Bool {
        guard let app = app(at: selection) else { return false }
        return launcher.isRunning(app)
    }

    var compactFavoriteSlots: [CompactFavoriteSlot] {
        let ordered = appIndex.orderedResults(
            query: "", visibility: visibility, favorites: favorites)
        let favoriteApps = ordered.prefix(while: favorites.isFavorite)
        if favoriteApps.count <= 5 { return favoriteApps.map(CompactFavoriteSlot.app) }
        return favoriteApps.prefix(4).map(CompactFavoriteSlot.app) + [.more]
    }

    func activateCompactFavorite(at index: Int) -> Bool {
        let slots = compactFavoriteSlots
        guard slots.indices.contains(index) else { return false }
        switch slots[index] {
        case .app(let app): launcher.launch(app)
        case .more: paletteCoordinator.expandFromCompact()
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        let results = results
        let showSections = vm.query.trimmingCharacters(in: .whitespaces).isEmpty
        let selected = row(at: selection)
        LauncherList(
            results: results,
            selectedID: app(at: selection)?.id,
            favoriteCount: showSections ? results.prefix(while: favorites.isFavorite).count : 0,
            showSections: showSections,
            scroll: scroll,
            calc: calc,
            calcSelected: isCalc(selected),
            onActivateCalc: { activateFirstRow() },
            onCalcActions: { openFirstRowActions() },
            aiIntent: aiReady,
            aiIntentSelected: isAIReady(selected),
            onActivateAI: { activateFirstRow() },
            aiPending: aiPending,
            aiPendingSelected: isAIPending(selected),
            onActivate: { launcher.launch($0, searchQuery: vm.query) },
            onActions: { app in
                if let index = rows.firstIndex(where: { row in
                    if case .app(let candidate) = row { return candidate == app }
                    return false
                }) { vm.selection = index }
                openActions()
            },
            funcSuggestions: functionSuggestions,
            funcSuggestionSelectedIndex: functionIndex(at: selection),
            onSelectFuncSuggestion: insert)
    }

    private func activateFirstRow() {
        vm.selection = 0
        activate(at: 0)
    }

    private func openFirstRowActions() {
        guard case .calc(let result) = rows.first, result.isActionable else { return }
        vm.selection = 0
        openActions()
    }

    private func insert(_ suggestion: CalcParser.FunctionSuggestion) {
        let trimmed = vm.query.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "=" || first == "＝" else { return }
        let expression = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        let parts = expression.split(omittingEmptySubsequences: false) {
            " +-*/^×÷%!(),".contains($0)
        }
        if let last = parts.last {
            let prefix = expression.dropLast(last.count)
            vm.query = String(first) + prefix + suggestion.name + "("
        } else {
            vm.query = String(first) + suggestion.name + "("
        }
    }

    private func isCalc(_ row: Row?) -> Bool {
        if case .calc = row { return true }
        return false
    }

    private func isAIReady(_ row: Row?) -> Bool {
        if case .aiReady = row { return true }
        return false
    }

    private func isAIPending(_ row: Row?) -> Bool {
        if case .aiPending = row { return true }
        return false
    }
}

/// A slot in the compact bar's favorites strip.
enum CompactFavoriteSlot {
    case app(AppEntry)
    case more

    var id: String {
        switch self {
        case .app(let app): return app.id
        case .more: return "__tinycast.more__"
        }
    }
}

struct CompactFavoritesRow: View {
    let slots: [CompactFavoriteSlot]
    let onLaunch: (AppEntry) -> Void
    let onOverflow: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                switch slot {
                case .app(let app):
                    CompactFavoriteButton(help: "\(app.name)  ⌘\(index + 1)") {
                        onLaunch(app)
                    } content: {
                        AppIconView(app: app)
                            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    }
                case .more:
                    CompactFavoriteButton(help: "Show all  ⌘\(index + 1)", action: onOverflow) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.Colors.controlSurface)
                                    .padding(Theme.Spacing.xxs))
                    }
                }
            }
        }
    }
}

private struct CompactFavoriteButton<Content: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content.contentShape(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
