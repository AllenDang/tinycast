import SwiftUI

struct RootPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var visibility: VisibilityStore
    @EnvironmentObject private var calcHistory: CalculatorHistoryStore
    @FocusState private var searchFocused: Bool
    @State private var showActions = false
    @State private var showAppMenu = false
    /// Bumped only when the selection should pull the scroll view with it — keyboard navigation and
    /// list resets. Mouse selection (click / right-click) targets an already-visible row, so it never
    /// bumps this and the list stays put.
    @State private var scrollToken = UUID()

    private var isQueryEmpty: Bool { vm.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Ordered launcher results — the single source of truth for the list, selection and activation.
    /// Empty query pins favorites to the top; otherwise plain ranked matches.
    private var appResults: [AppEntry] {
        // Visibility filtering stays downstream of `matches` so its one-deep memo cache is
        // never keyed on hidden state; hidden favorites drop out here too.
        let base = appIndex.matches(vm.query).filter(visibility.isVisible)
        guard isQueryEmpty, !favorites.keys.isEmpty else { return base }
        let split = favorites.ordered(base)
        return split.favorites + split.rest
    }
    private var clipResults: [ClipboardItem] { store.search(vm.query) }
    private var histResults: [CalcHistoryEntry] { calcHistory.search(vm.query) }

    /// Inline calculator answer for the current query — live in the launcher *and* in the
    /// Calculator History search (Raycast lets you do math right from history). When present it
    /// occupies flat selection index 0 and every row access below shifts by `calcCount`.
    private var calcResult: CalcResult? {
        vm.mode != .clipboard ? CalcMemo.evaluate(vm.query) : nil
    }
    private var calcCount: Int { calcResult == nil ? 0 : 1 }

    private var resultCount: Int {
        switch vm.mode {
        case .launcher: return appResults.count + calcCount
        case .clipboard: return clipResults.count
        case .calculatorHistory: return histResults.count + calcCount
        }
    }
    /// Selection clamped into the current results — the single source of truth for highlight,
    /// preview and activation so the list and preview can never disagree.
    private var selection: Int { resultCount == 0 ? 0 : min(max(vm.selection, 0), resultCount - 1) }

    var body: some View {
        // Filter once per render for the active mode only; event handlers (rare) use the computed
        // properties above. Avoids running the matcher/search several times for a single render.
        let apps = vm.mode == .launcher ? appResults : []
        let clips = vm.mode == .clipboard ? clipResults : []
        let hist = vm.mode == .calculatorHistory ? histResults : []
        // Every count/selection below derives from this one calc/offset pair — the flat selection
        // index must always match the visible row order, calc card included.
        let calc = calcResult
        let offset = calc == nil ? 0 : 1
        let count = apps.count + offset + clips.count + hist.count  // only the active mode is non-empty
        let sel = count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
        let calcSelected = calc != nil && sel == 0
        let showSections = vm.mode == .launcher && isQueryEmpty
        let favoriteCount =
            showSections ? apps.prefix(while: { favorites.isFavorite($0) }).count : 0
        let selectedApp = apps.indices.contains(sel - offset) ? apps[sel - offset] : nil
        let selectedClip = clips.indices.contains(sel) ? clips[sel] : nil
        let selectedHist = hist.indices.contains(sel - offset) ? hist[sel - offset] : nil

        // The results layer fills the whole panel; the search header and action bar float on top
        // as translucent Liquid Glass bars (via safeAreaInset). The list scrolls *behind* them and
        // stays faintly visible through the glass — the Raycast look, with no hard dividers.
        return content(
            apps: apps, clips: clips, hist: hist, calc: calc, selection: sel,
            favoriteCount: favoriteCount, showSections: showSections
        )
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        // Menus are in-window overlays anchored to a bottom corner, so they stay clipped inside the
        // panel and sit over the bottom bar — never a system popover spilling outside the window.
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
                    calc: calcSelected ? calc : nil
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomTrailing))
            }
        }
        .frame(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight)
        .background(Color.black.opacity(0.40))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // Every show bumps focusToken — refocus search and drop any menu left open from last time
        // (e.g. when the palette was dismissed by clicking away while a context menu was up).
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
            move(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            move(-1)
            return .handled
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
        // Bare backspace (back out of a sub-screen when the search is empty) is intercepted by
        // PalettePanel.sendEvent — the field editor consumes it before onKeyPress could fire.
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            switch vm.mode {
            case .clipboard:
                deleteSelectedClip()
            case .calculatorHistory:
                deleteSelectedHistoryEntry()
            case .launcher:
                return .ignored
            }
            return .handled
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            // Clipboard and Calculator History are sub-screens of the root search, so their header
            // icon is a back chevron (Raycast style) instead of a mode glyph.
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
            TextField(vm.mode.placeholder, text: $vm.query)
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
        .background(EdgeFade(edge: .top))
    }

    @ViewBuilder
    private func content(
        apps: [AppEntry], clips: [ClipboardItem], hist: [CalcHistoryEntry], calc: CalcResult?,
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
            // Empty history: center one message across the whole panel rather than wedging it into
            // the narrow list column beside a blank preview.
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
                        .fill(Color.primary.opacity(0.10))
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
        }
    }

    /// The bottom-right actions popover for the current mode's selection.
    @ViewBuilder
    private func actionsMenu(
        app: AppEntry?, clip: ClipboardItem?, hist: CalcHistoryEntry?, calc: CalcResult?
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
        }
    }

    private var bottomBar: some View {
        // No bar — just floating glass buttons over the list, with a soft dark fade up from the
        // bottom edge so they read clearly without any hard-edged strip.
        HStack(spacing: 0) {
            appMenuButton
            Spacer()
            actionPill
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
        .background(EdgeFade(edge: .bottom))
    }

    private var appMenuButton: some View {
        Button {
            withAnimation(Self.menuAnimation) { showAppMenu.toggle() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.menuButton, height: Theme.Size.menuButton)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .frosted(in: Circle())
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

    /// Pill label for the current selection. Reads the memoized `appResults`, so the extra
    /// lookup during render is cheap.
    private var actionPillLabel: String {
        switch vm.mode {
        case .clipboard:
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

    private var actionPill: some View {
        Button(action: activateSelection) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(actionPillLabel)
                Image(systemName: "return")
            }
            .font(Theme.Typography.pill)
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .frosted(in: Capsule())
    }

    private func closeMenus() {
        withAnimation(Self.menuAnimation) {
            showActions = false
            showAppMenu = false
        }
    }

    /// Inset of the menu panels from the window's bottom corners. Kept just inside the panel's
    /// rounded corner so the menu's own corner isn't clipped.
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

    /// Tab flips launcher↔clipboard; Calculator History (entered via its command) exits back to
    /// the launcher rather than joining the cycle.
    private func toggleMode() {
        vm.mode = vm.mode == .launcher ? .clipboard : .launcher
    }

    /// Back out of Calculator History to a fresh root search — `prepare` is the same reset used
    /// when the palette is shown (clears query/selection, bumps focusToken to refocus the field).
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
                // A fresh calculation typed into the history search: copy + record like the
                // launcher card (error cards no-op).
                core.copyCalculatorResult(calcResult)
                return
            }
            let index = selection - calcCount
            guard histResults.indices.contains(index) else { return }
            core.copyHistoryEntry(histResults[index])
        }
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

private struct EdgeFade: View {
    let edge: VerticalEdge

    var body: some View {
        let start: UnitPoint = edge == .top ? .top : .bottom
        let end: UnitPoint = edge == .top ? .bottom : .top
        let fade = LinearGradient(
            stops: [
                .init(color: .black.opacity(1), location: 0.0),
                .init(color: .black.opacity(0.90), location: 0.4),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: start, endPoint: end
        )
        VisualEffectView(material: .hudWindow, blending: .withinWindow)
            .mask(fade)
    }
}
