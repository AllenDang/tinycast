import SwiftUI

struct RootPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var visibility: VisibilityStore
    @EnvironmentObject private var calcHistory: CalculatorHistoryStore
    @EnvironmentObject private var emojiIndex: EmojiIndex
    @EnvironmentObject private var frequentEmoji: FrequentEmojiStore
    /// Observed so a skin tone changed in Settings re-renders the grid glyphs immediately.
    @ObservedObject private var settings = AppCore.shared.settings
    @FocusState private var searchFocused: Bool
    @State private var showActions = false
    @State private var showAppMenu = false
    /// Bumped only when the selection should pull the scroll view with it (keyboard nav, list resets); mouse selection targets a visible row, so it leaves this and the list put.
    @State private var scrollToken = UUID()

    private var isQueryEmpty: Bool { vm.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Ordered launcher results (the single source of truth for list, selection and activation): empty query pins favorites to the top, otherwise plain ranked matches.
    private var appResults: [AppEntry] {
        // Visibility filtering stays downstream of `matches` so its one-deep memo cache is never keyed on hidden state; hidden favorites drop out here too.
        let base = appIndex.matches(vm.query).filter(visibility.isVisible)
        guard isQueryEmpty, !favorites.keys.isEmpty else { return base }
        let split = favorites.ordered(base)
        return split.favorites + split.rest
    }
    private var clipResults: [ClipboardItem] { store.search(vm.query) }
    private var histResults: [CalcHistoryEntry] { calcHistory.search(vm.query) }
    private var emojiSections: [EmojiGridSection] {
        EmojiGrid.sections(query: vm.query, index: emojiIndex, frequent: frequentEmoji)
    }
    /// Flat grid order across sections — what `vm.selection` indexes in emoji mode.
    private var emojiResults: [EmojiEntry] { emojiSections.flatMap(\.entries) }

    /// Inline calculator answer for the current query, live in both the launcher and Calculator History search; when present it occupies flat selection index 0 so rows shift by `calcCount`.
    private var calcResult: CalcResult? {
        vm.mode == .launcher || vm.mode == .calculatorHistory ? CalcMemo.evaluate(vm.query) : nil
    }
    private var calcCount: Int { calcResult == nil ? 0 : 1 }

    private var resultCount: Int {
        switch vm.mode {
        case .launcher: return appResults.count + calcCount
        case .clipboard: return clipResults.count
        case .calculatorHistory: return histResults.count + calcCount
        case .emoji: return emojiResults.count
        }
    }
    /// Selection clamped into the current results — the single source of truth for highlight, preview and activation so the list and preview can never disagree.
    private var selection: Int { resultCount == 0 ? 0 : min(max(vm.selection, 0), resultCount - 1) }

    var body: some View {
        // Filter once per render for the active mode only, so the matcher/search doesn't run several times per render (rare event handlers use the computed properties above).
        let apps = vm.mode == .launcher ? appResults : []
        let clips = vm.mode == .clipboard ? clipResults : []
        let hist = vm.mode == .calculatorHistory ? histResults : []
        let emojiSections = vm.mode == .emoji ? emojiSections : []
        let emojis = emojiSections.flatMap(\.entries)
        // Every count/selection below derives from this one calc/offset pair — the flat selection index must always match the visible row order, calc card included.
        let calc = calcResult
        let offset = calc == nil ? 0 : 1
        // Only the active mode is non-empty.
        let count = apps.count + offset + clips.count + hist.count + emojis.count
        let sel = count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
        let calcSelected = calc != nil && sel == 0
        let showSections = vm.mode == .launcher && isQueryEmpty
        let favoriteCount =
            showSections ? apps.prefix(while: { favorites.isFavorite($0) }).count : 0
        let selectedApp = apps.indices.contains(sel - offset) ? apps[sel - offset] : nil
        let selectedClip = clips.indices.contains(sel) ? clips[sel] : nil
        let selectedHist = hist.indices.contains(sel - offset) ? hist[sel - offset] : nil
        let selectedEmoji = emojis.indices.contains(sel) ? emojis[sel] : nil

        // Results fill the panel; header and action bar float over it as transparent safeAreaInset overlays, each list's `edgeDissolve` ghosting rows under the bars (the native scroll edge effect renders a hard rectangle inside a transparent panel).
        return content(
            apps: apps, clips: clips, hist: hist, emojiSections: emojiSections, calc: calc,
            selection: sel, favoriteCount: favoriteCount, showSections: showSections
        )
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(selectedEmoji: selectedEmoji) }
        // Menus are in-window overlays anchored to a bottom corner, so they stay clipped inside the panel — never a system popover spilling outside the window.
        .overlay {
            if showAppMenu || showActions {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeMenus)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showAppMenu {
                appMenu
                    .padding(Self.menuInset)
                    .transition(Self.menuTransition(.bottomLeading))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showActions {
                actionsMenu(
                    app: selectedApp, clip: selectedClip, hist: selectedHist,
                    emoji: selectedEmoji, calc: calcSelected ? calc : nil
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomTrailing))
            }
        }
        .frame(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight)
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // Every show bumps focusToken — refocus search and drop any menu left open from last time (e.g. dismissed by clicking away with a context menu up).
        .onChange(of: vm.focusToken) {
            searchFocused = true
            showActions = false
            showAppMenu = false
        }
        .onChange(of: vm.query) {
            vm.selection = 0
            scrollToken = UUID()
        }
        .onChange(of: vm.mode) {
            vm.selection = 0
            showActions = false
            scrollToken = UUID()
        }
        .onAppear { searchFocused = true }
        .onKeyPress(.downArrow) {
            if vm.mode == .emoji { moveEmojiRow(1) } else { move(1) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if vm.mode == .emoji { moveEmojiRow(-1) } else { move(-1) }
            return .handled
        }
        // Horizontal arrows step the emoji grid; everywhere else they stay with the field editor's caret.
        .onKeyPress(.leftArrow) {
            guard vm.mode == .emoji else { return .ignored }
            move(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard vm.mode == .emoji else { return .ignored }
            move(1)
            return .handled
        }
        // ⌘↵ copies / ⌥↵ pastes-in-place the selected emoji; plain ↵ falls through to the field's onSubmit.
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard vm.mode == .emoji, emojiResults.indices.contains(selection) else {
                return .ignored
            }
            if press.modifiers.contains(.command) {
                core.copyEmoji(emojiResults[selection])
                return .handled
            }
            if press.modifiers.contains(.option) {
                core.pasteEmojiKeepingWindowOpen(emojiResults[selection])
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if showActions || showAppMenu {
                closeMenus()
                return .handled
            }
            core.hidePalette()
            return .handled
        }
        .onKeyPress(.tab) {
            toggleMode()
            return .handled
        }
        .onKeyPress(keys: [","], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            core.showSettings()
            return .handled
        }
        // ⌘K toggles the actions panel for the current selection.
        .onKeyPress(keys: ["k"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            guard resultCount > 0 else { return .handled }
            withAnimation(Self.menuAnimation) { showActions.toggle() }
            return .handled
        }
        // Bare backspace (back out of a sub-screen when the search is empty) is intercepted by PalettePanel.sendEvent — the field editor consumes it before onKeyPress could fire.
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            switch vm.mode {
            case .clipboard:
                deleteSelectedClip()
            case .calculatorHistory:
                deleteSelectedHistoryEntry()
            case .launcher, .emoji:
                return .ignored
            }
            return .handled
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            // Clipboard and Calculator History are sub-screens of the root search, so their header icon is a back chevron instead of a mode glyph.
            if vm.mode != .launcher {
                Button(action: exitToLauncher) {
                    Image(systemName: "chevron.left")
                        .font(Theme.Typography.headerIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: vm.mode.systemImage)
                    .font(Theme.Typography.headerIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            TextField(
                "", text: $vm.query,
                prompt: Text(vm.mode.placeholder).foregroundStyle(Theme.Colors.textTertiary)
            )
            .textFieldStyle(.plain)
            .font(Theme.Typography.searchField)
            .focused($searchFocused)
            .onSubmit(activateSelection)
        }
        // Align the search icon with the list rows and section headers below (list inset + row inset).
        .padding(.horizontal, Theme.Spacing.md * 2)
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Spacing.md)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func content(
        apps: [AppEntry], clips: [ClipboardItem], hist: [CalcHistoryEntry],
        emojiSections: [EmojiGridSection], calc: CalcResult?,
        selection: Int, favoriteCount: Int, showSections: Bool
    ) -> some View {
        switch vm.mode {
        case .launcher:
            let offset = calc == nil ? 0 : 1
            let calcSelected = calc != nil && selection == 0
            let appIndex = selection - offset
            let selectedID = apps.indices.contains(appIndex) ? apps[appIndex].id : nil
            LauncherList(
                results: apps,
                selectedID: calcSelected ? nil : selectedID,
                favoriteCount: favoriteCount,
                showSections: showSections,
                scrollToken: scrollToken,
                calc: calc,
                calcSelected: calcSelected,
                onActivateCalc: {
                    vm.selection = 0
                    activateSelection()
                },
                onCalcActions: {
                    guard let calc, case .value = calc.payload else { return }
                    vm.selection = 0
                    withAnimation(Self.menuAnimation) { showActions = true }
                },
                onActions: { app in
                    if let index = apps.firstIndex(of: app) { vm.selection = index + offset }
                    withAnimation(Self.menuAnimation) { showActions = true }
                }
            )
        case .clipboard:
            // Empty history: center one message across the whole panel rather than wedging it into the narrow list column beside a blank preview.
            if clips.isEmpty {
                EmptyResults(text: "Clipboard history is empty")
            } else {
                let selected = clips.indices.contains(selection) ? clips[selection] : nil
                HStack(spacing: 0) {
                    ClipboardList(
                        results: clips,
                        selectedID: selected?.id,
                        scrollToken: scrollToken,
                        onSelect: { item in vm.selection = clips.firstIndex(of: item) ?? 0 },
                        onActivate: activateSelection,
                        onActions: { item in
                            if let index = clips.firstIndex(of: item) { vm.selection = index }
                            withAnimation(Self.menuAnimation) { showActions = true }
                        }
                    )
                    .frame(width: Theme.Size.clipboardListWidth)
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(width: 1)
                    ClipboardPreview(item: selected)
                }
            }
        case .calculatorHistory:
            if hist.isEmpty && calc == nil {
                EmptyResults(
                    text: isQueryEmpty ? "No calculations yet" : "No matching calculations")
            } else {
                let offset = calc == nil ? 0 : 1
                let calcSelected = calc != nil && selection == 0
                let histIndex = selection - offset
                let selected = hist.indices.contains(histIndex) ? hist[histIndex] : nil
                CalculatorHistoryList(
                    results: hist,
                    selectedID: calcSelected ? nil : selected?.id,
                    scrollToken: scrollToken,
                    calc: calc,
                    calcSelected: calcSelected,
                    onActivateCalc: {
                        vm.selection = 0
                        activateSelection()
                    },
                    onCalcActions: {
                        guard let calc, case .value = calc.payload else { return }
                        vm.selection = 0
                        withAnimation(Self.menuAnimation) { showActions = true }
                    },
                    onSelect: { entry in
                        if let index = hist.firstIndex(of: entry) { vm.selection = index + offset }
                    },
                    onActivate: activateSelection,
                    onActions: { entry in
                        if let index = hist.firstIndex(of: entry) { vm.selection = index + offset }
                        withAnimation(Self.menuAnimation) { showActions = true }
                    }
                )
            }
        case .emoji:
            if !emojiIndex.isLoaded {
                EmptyResults(text: "Loading emoji…")
            } else if emojiSections.isEmpty {
                EmptyResults(text: "No emoji found")
            } else {
                EmojiGridView(
                    sections: emojiSections,
                    selection: selection,
                    tone: settings.emojiSkinTone,
                    scrollToken: scrollToken,
                    onSelect: { vm.selection = $0 },
                    onActivate: activateSelection,
                    onActions: { flat in
                        vm.selection = flat
                        withAnimation(Self.menuAnimation) { showActions = true }
                    }
                )
            }
        }
    }

    /// The bottom-right actions popover for the current mode's selection.
    @ViewBuilder
    private func actionsMenu(
        app: AppEntry?, clip: ClipboardItem?, hist: CalcHistoryEntry?, emoji: EmojiEntry?,
        calc: CalcResult?
    ) -> some View {
        switch vm.mode {
        case .launcher:
            if let calc {
                CalcActionsMenu(result: calc) { closeMenus() }
                    .environmentObject(core)
            } else if let app {
                AppActionsMenu(app: app) { closeMenus() }
                    .environmentObject(core)
                    .environmentObject(favorites)
            }
        case .clipboard:
            if let clip {
                ClipboardActionsMenu(item: clip) { closeMenus() }
                    .environmentObject(core)
                    .environmentObject(store)
            }
        case .calculatorHistory:
            if let calc {
                CalcActionsMenu(result: calc) { closeMenus() }
                    .environmentObject(core)
            } else if let hist {
                CalcHistoryActionsMenu(entry: hist) { closeMenus() }
                    .environmentObject(core)
                    .environmentObject(calcHistory)
            }
        case .emoji:
            if let emoji {
                EmojiActionsMenu(entry: emoji) { closeMenus() }
                    .environmentObject(core)
            }
        }
    }

    private func bottomBar(selectedEmoji: EmojiEntry?) -> some View {
        // No bar — just floating glass controls over the list; the edge dissolve ghosts rows passing beneath, so the buttons read clearly without a hard-edged strip.
        HStack(spacing: Theme.Spacing.md) {
            appMenuButton
            if let selectedEmoji {
                // Raycast-style readout of the selected cell, since grid cells have no room for a label.
                HStack(spacing: Theme.Spacing.sm) {
                    Text(selectedEmoji.display(tone: settings.emojiSkinTone))
                    Text(selectedEmoji.displayName)
                        .font(Theme.Typography.bar)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 28)
                .frosted(in: Capsule())
            }
            Spacer()
            actionGroup
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    private var appMenuButton: some View {
        MenuCircleButton {
            withAnimation(Self.menuAnimation) { showAppMenu.toggle() }
        }
    }

    /// The footer control group: primary action and the Actions toggle sharing one glass capsule.
    private var actionGroup: some View {
        HStack(spacing: 2) {
            BarButton(action: activateSelection) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(actionPillLabel)
                        .font(Theme.Typography.bar)
                        .foregroundStyle(.primary)
                    KeyCapChip(text: "↵", style: .outline)
                }
            }
            BarButton(action: { withAnimation(Self.menuAnimation) { showActions.toggle() } }) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Actions")
                        .font(Theme.Typography.bar)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    HStack(spacing: 2) {
                        KeyCapChip(text: "⌘", style: .outline)
                        KeyCapChip(text: "K", style: .outline)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
    }

    private var appMenu: some View {
        PopoverMenu {
            PopoverMenuRow(title: "About Tinycast", systemImage: "info.circle") {
                closeMenus()
                core.showAbout()
            }
            PopoverMenuRow(title: "Settings", systemImage: "gearshape", shortcut: "⌘,") {
                closeMenus()
                core.showSettings()
            }
        }
    }

    /// Pill label for the current selection; reads the memoized `appResults`, so the extra render lookup is cheap.
    private var actionPillLabel: String {
        switch vm.mode {
        case .clipboard, .emoji:
            return "Paste"
        case .calculatorHistory:
            return "Copy Answer"
        case .launcher:
            if calcCount > 0 && selection == 0 { return "Copy Answer" }
            let apps = appResults
            let index = selection - calcCount
            let selected = apps.indices.contains(index) ? apps[index] : nil
            switch selected?.kind {
            case .systemSettings: return "Open"
            case .command: return "Run Command"
            default: return "Open Application"
            }
        }
    }

    private func closeMenus() {
        withAnimation(Self.menuAnimation) {
            showActions = false
            showAppMenu = false
        }
    }

    /// Inset of the menu panels from the window's bottom corners, kept just inside the rounded corner so the menu's own corner isn't clipped.
    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: 0.14)

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
    }

    private func deleteSelectedClip() {
        guard clipResults.indices.contains(selection) else { return }
        store.remove(clipResults[selection])
    }

    private func deleteSelectedHistoryEntry() {
        let index = selection - calcCount  // the inline calc card can't be deleted
        guard histResults.indices.contains(index) else { return }
        calcHistory.remove(histResults[index])
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        guard resultCount > 0 else { return }
        vm.selection = min(max(selection + delta, 0), resultCount - 1)
        scrollToken = UUID()
    }

    /// Vertical grid move: one visual row within a section, spilling into the neighbor while keeping the column.
    private func moveEmojiRow(_ delta: Int) {
        let geometry = EmojiGridGeometry(
            counts: emojiSections.map(\.entries.count), columns: EmojiGrid.columns)
        guard resultCount > 0 else { return }
        vm.selection = delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        scrollToken = UUID()
    }

    /// Tab flips launcher↔clipboard; Calculator History (entered via its command) exits back to the launcher rather than joining the cycle.
    private func toggleMode() {
        vm.mode = vm.mode == .launcher ? .clipboard : .launcher
    }

    /// Back out to a fresh root search — `prepare` is the same reset used when the palette is shown (clears query/selection, bumps focusToken to refocus the field).
    private func exitToLauncher() {
        vm.prepare(mode: .launcher)
    }

    private func activateSelection() {
        switch vm.mode {
        case .launcher:
            if let calcResult, selection == 0 {
                // Error cards no-op — copyCalculatorResult only acts on value payloads.
                core.copyCalculatorResult(calcResult)
                return
            }
            let index = selection - calcCount
            guard appResults.indices.contains(index) else { return }
            core.launch(appResults[index])
        case .clipboard:
            guard clipResults.indices.contains(selection) else { return }
            core.paste(clipResults[selection])
        case .calculatorHistory:
            if let calcResult, selection == 0 {
                // A fresh calculation typed into the history search: copy + record like the launcher card (error cards no-op).
                core.copyCalculatorResult(calcResult)
                return
            }
            let index = selection - calcCount
            guard histResults.indices.contains(index) else { return }
            core.copyHistoryEntry(histResults[index])
        case .emoji:
            guard emojiResults.indices.contains(selection) else { return }
            core.pasteEmoji(emojiResults[selection])
        }
    }
}

/// The footer's glass menu circle; hover lives here so a mouse sweep never re-renders the palette body.
private struct MenuCircleButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.title3)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.menuButton, height: Theme.Size.menuButton)
                .background(Circle().fill(hovered ? Theme.Colors.rowHover : Color.clear))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
    }
}

/// Footer button: bare label at rest, a faint capsule fill on hover.
private struct BarButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 28)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct EmptyResults: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
