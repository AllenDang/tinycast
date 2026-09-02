import SwiftUI

struct RootPaletteView: View {
    @Environment(PaletteCoordinator.self) private var paletteCoordinator
    @Environment(LauncherCoordinator.self) private var launcherCoordinator
    @Environment(AICommandCoordinator.self) private var aiCoordinator
    @Environment(CalculatorCoordinator.self) private var calculatorCoordinator
    @Environment(ClipboardCoordinator.self) private var clipboardCoordinator
    @Environment(EmojiCoordinator.self) private var emojiCoordinator
    @Environment(QuicklinkCoordinator.self) private var quicklinkCoordinator
    @Environment(UninstallCoordinator.self) private var uninstallCoordinator
    @Environment(PaletteState.self) private var vm
    @Environment(AppIndex.self) private var appIndex
    @Environment(ClipboardStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(VisibilityStore.self) private var visibility
    @Environment(CalculatorHistoryStore.self) private var calcHistory
    @Environment(CurrencyRateStore.self) private var currencyRates
    @Environment(EmojiIndex.self) private var emojiIndex
    @Environment(FrequentEmojiStore.self) private var frequentEmoji
    @Environment(UninstallSession.self) private var uninstall
    @Environment(QuicklinkStore.self) private var quicklinks
    @Environment(QuicklinkArgumentSession.self) private var quicklinkArguments
    @Environment(AICommandStore.self) private var aiCommands
    @Environment(AIProviderStore.self) private var aiProvider
    @Environment(AICommandSession.self) private var aiCommandSession
    @Environment(AppSettings.self) private var settings
    @FocusState private var searchFocused: Bool
    @State private var showActions = false
    @State private var showAppMenu = false
    @State private var selectionIsRunning = false
    @State private var menuSelection = 0
    @State private var scroll = ScrollIntent(kind: .top)
    private var isCollapsed: Bool { paletteCoordinator.paletteIsCollapsed }

    private var launcherScreen: LauncherScreen {
        LauncherScreen(
            appIndex: appIndex, favorites: favorites, visibility: visibility,
            currencyRates: currencyRates, aiCommands: aiCommands, aiProvider: aiProvider,
            launcher: launcherCoordinator, aiCoordinator: aiCoordinator,
            calculatorCoordinator: calculatorCoordinator,
            paletteCoordinator: paletteCoordinator,
            vm: vm, running: selectionIsRunning, openActions: openActions)
    }

    private var screen: any PaletteScreen {
        switch vm.mode {
        case .launcher:
            return launcherScreen
        case .uninstall:
            return UninstallScreen(
                session: uninstall, coordinator: uninstallCoordinator, vm: vm,
                openActions: openActions)
        case .quicklinkArguments:
            return QuicklinkArgumentsScreen(
                session: quicklinkArguments, coordinator: quicklinkCoordinator, vm: vm,
                scrollToTop: { scroll = ScrollIntent(kind: .top) })
        case .quicklinks:
            return QuicklinkListScreen(
                store: quicklinks, coordinator: quicklinkCoordinator,
                palette: paletteCoordinator, vm: vm, openActions: openActions)
        case .aiCommand:
            return AICommandScreen(
                session: aiCommandSession, coordinator: aiCoordinator)
        case .emoji:
            return EmojiScreen(
                index: emojiIndex, frequent: frequentEmoji,
                coordinator: emojiCoordinator, vm: vm,
                tone: settings.emojiSkinTone, openActions: openActions)
        case .clipboard:
            return ClipboardScreen(
                store: store, coordinator: clipboardCoordinator, vm: vm,
                openActions: openActions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .calculatorHistory:
            return CalculatorHistoryScreen(
                history: calcHistory, currencyRates: currencyRates,
                coordinator: calculatorCoordinator, vm: vm, openActions: openActions)
        }
    }

    private var resultCount: Int { screen.rows.count }

    private var selection: Int {
        PaletteRowIndex(sectionCounts: [resultCount]).clamped(vm.selection)
    }

    private var menuOpen: Bool { (showActions && actionsMenuAvailable) || showAppMenu }

    private var searchFieldFrozen: Bool { menuOpen || vm.mode == .aiCommand }

    private var actionsContent: PopoverMenuContent? { screen.actions(at: selection) }

    private var actionsMenuAvailable: Bool { actionsContent != nil }

    /// The bottom-left app menu content (About / Settings).
    private var appMenuContent: PopoverMenuContent {
        PopoverMenuContent(items: [
            PopoverMenuItem(title: "About Tinycast", systemImage: "info.circle") {
                paletteCoordinator.showAbout()
            },
            PopoverMenuItem(title: "Settings", systemImage: "gearshape", shortcut: "⌘,") {
                paletteCoordinator.showSettings()
            }
        ])
    }

    private var menuContent: PopoverMenuContent? {
        if showActions { return actionsContent }
        if showAppMenu { return appMenuContent }
        return nil
    }

    var body: some View {
        let activeScreen = screen
        let count = activeScreen.rows.count
        let selected = PaletteRowIndex(sectionCounts: [count]).clamped(vm.selection)
        let showsPrimaryAction =
            (count > 0 || vm.mode == .quicklinkArguments)
            && activeScreen.hasPrimaryAction(at: selected)
        let showsActionsMenu = activeScreen.actions(at: selected) != nil

        return Group {
            if isCollapsed {
                Color.clear
            } else {
                activeScreen.body(selection: selected, scroll: scroll)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isCollapsed {
                bottomBar(
                    pillLabel: activeScreen.primaryActionTitle, showsPrimaryAction: showsPrimaryAction,
                    showsActionsMenu: showsActionsMenu)
            }
        }
        .overlay {
            if menuOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeMenus)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showAppMenu {
                let content = appMenuContent
                PopoverMenu(
                    header: content.header, items: content.items, selection: $menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomLeading))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showActions, let content = actionsContent {
                PopoverMenu(
                    header: content.header, items: content.items, selection: $menuSelection,
                    onActivate: activateMenuItem
                )
                .padding(Self.menuInset)
                .transition(Self.menuTransition(.bottomTrailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .onChange(of: vm.focusToken) {
            searchFocused = true
            showActions = false
            showAppMenu = false
        }
        .onChange(of: vm.query) {
            vm.selection = 0
            scroll = ScrollIntent(kind: .top)
        }
        .onChange(of: vm.mode) {
            vm.selection = 0
            showActions = false
            scroll = ScrollIntent(kind: .top)
            // Every way out of the Uninstall screen: back chevron, bare backspace, a fresh summon.
            if vm.mode != .uninstall { uninstall.cancel() }
            // Same for a half-filled argument form: leaving the screen abandons the pending open.
            if vm.mode != .quicklinkArguments {
                quicklinkCoordinator.cancelQuicklinkArguments()
            }
            if vm.mode != .aiCommand { aiCoordinator.cancel() }
            vm.searchFieldFrozen = searchFieldFrozen
        }
        .onChange(of: vm.resetToken) {
            scroll = ScrollIntent(kind: .top)
        }
        .onChange(of: actionsMenuAvailable) { _, available in
            if !available, showActions { showActions = false }
        }
        .onChange(of: showActions) {
            if showActions {
                showAppMenu = false
                menuSelection = 0
            }
            vm.searchFieldFrozen = searchFieldFrozen
        }
        .onChange(of: showAppMenu) {
            if showAppMenu {
                showActions = false
                menuSelection = 0
            }
            vm.searchFieldFrozen = searchFieldFrozen
        }
        .onAppear { searchFocused = true }
        .onChange(of: paletteCoordinator.paletteIsCollapsed) {
            paletteCoordinator.syncPaletteSize()
        }
        .onKeyPress(keys: ["1", "2", "3", "4", "5"], phases: .down) { press in
            guard isCollapsed, settings.showFavoritesInCompactMode,
                press.modifiers.contains(.command),
                let digit = press.key.character.wholeNumberValue
            else { return .ignored }
            return launcherScreen.activateCompactFavorite(at: digit - 1) ? .handled : .ignored
        }
        .onKeyPress(.downArrow) {
            if isCollapsed {
                vm.selection = 0
                paletteCoordinator.expandFromCompact()
                return .handled
            }
            if menuOpen {
                moveMenu(1)
                return .handled
            }
            moveVertically(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            if isCollapsed { return .ignored }
            if menuOpen {
                moveMenu(-1)
                return .handled
            }
            moveVertically(-1)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if menuOpen { return .handled }
            return moveHorizontally(-1) ? .handled : .ignored
        }
        .onKeyPress(.rightArrow) {
            if menuOpen { return .handled }
            return moveHorizontally(1) ? .handled : .ignored
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            let command = press.modifiers.contains(.command)
            let option = press.modifiers.contains(.option)
            if menuOpen, !command, !option {
                activateMenuItem(menuSelection)
                return .handled
            }
            guard command || option else { return .ignored }
            if command { return screen.secondary(at: selection) ? .handled : .ignored }
            return screen.perform(.alternateActivate, at: selection) ? .handled : .ignored
        }
        .onKeyPress(.escape) {
            if showActions || showAppMenu {
                closeMenus()
                return .handled
            }
            if vm.mode == .aiCommand {
                aiCoordinator.cancel()
                vm.prepare(mode: .launcher)
                return .handled
            }
            paletteCoordinator.hidePalette()
            return .handled
        }
        .onKeyPress(.tab) {
            if menuOpen { return .handled }
            toggleMode()
            return .handled
        }
        // ⌘K toggles the actions panel for the current selection.
        .onKeyPress(keys: ["k"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            guard !isCollapsed else { return .handled }
            guard resultCount > 0 else { return .handled }
            guard actionsMenuAvailable else { return .handled }
            toggleActions()
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            if menuOpen { return .handled }
            guard press.modifiers.contains(.command) else { return .ignored }
            return screen.perform(.delete, at: selection) ? .handled : .ignored
        }
        .onKeyPress(keys: ["p"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            return screen.perform(.pin, at: selection) ? .handled : .ignored
        }
        .onKeyPress(keys: ["q", "Q"], phases: .down) { press in
            guard press.modifiers.contains(.control), press.modifiers.contains(.shift),
                !isCollapsed
            else { return .ignored }
            return screen.perform(.quit, at: selection) ? .handled : .ignored
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            if vm.mode != .launcher {
                Button(action: exitToLauncher) {
                    Image(systemName: "chevron.left")
                        .font(Theme.Typography.headerIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: Theme.Size.headerIconSlot)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: vm.mode.systemImage)
                    .font(Theme.Typography.headerIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.Size.headerIconSlot)
            }
            searchField
            if isCollapsed, settings.showFavoritesInCompactMode {
                let slots = launcherScreen.compactFavoriteSlots
                if !slots.isEmpty {
                    CompactFavoritesRow(
                        slots: slots,
                        onLaunch: { launcherCoordinator.launch($0) },
                        onOverflow: { paletteCoordinator.expandFromCompact() }
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md * 2)
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    private var searchPrompt: String {
        vm.mode == .quicklinkArguments ? quicklinkArguments.prompt : vm.mode.placeholder
    }

    private var searchField: some View {
        @Bindable var vm = vm
        return TextField("", text: $vm.query)
            .textFieldStyle(.plain)
            .font(Theme.Typography.searchField)
            .tint(.white)
            .focused($searchFocused)
            .onSubmit(activateSelection)
            .background(alignment: .leading) {
                if vm.query.isEmpty && !vm.isComposing {
                    Text(searchPrompt)
                        .font(Theme.Typography.searchField)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        // Never a click target: tapping the placeholder must still land the caret.
                        .allowsHitTesting(false)
                }
            }
            // The prompt used to carry this; without it the field would be unlabelled.
            .accessibilityLabel(Text(searchPrompt))
    }

    /// The Uninstall screen's primary action is destructive, so its pill isn't white.
    private var pillTint: Color {
        vm.mode == .uninstall ? Theme.Colors.destructive : .primary
    }

    private func bottomBar(
        pillLabel: String, showsPrimaryAction: Bool, showsActionsMenu: Bool
    ) -> some View {
        HStack(spacing: 0) {
            appMenuButton
            Spacer()
            if showsPrimaryAction || showsActionsMenu {
                actionGroup(
                    pillLabel: pillLabel, showsPrimaryAction: showsPrimaryAction,
                    showsActionsMenu: showsActionsMenu)
            }
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
    private func actionGroup(
        pillLabel: String, showsPrimaryAction: Bool, showsActionsMenu: Bool
    ) -> some View {
        HStack(spacing: 2) {
            if showsPrimaryAction {
                BarButton(action: activateSelection) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(pillLabel)
                            .font(Theme.Typography.bar)
                            .foregroundStyle(pillTint)
                        KeyCapChip(text: "↵", style: .outline)
                    }
                }
            }
            if showsActionsMenu {
                BarButton(action: toggleActions) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Actions")
                            .font(Theme.Typography.bar)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        HStack(spacing: Theme.Spacing.xxs) {
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: "K", style: .outline)
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .frosted(in: Capsule())
    }

    private func openActions() {
        selectionIsRunning = screen.isRunning(at: selection)
        guard actionsMenuAvailable else { return }
        withAnimation(Self.menuAnimation) { showActions = true }
    }

    private func toggleActions() {
        if showActions {
            withAnimation(Self.menuAnimation) { showActions = false }
        } else {
            openActions()
        }
    }

    private func closeMenus() {
        withAnimation(Self.menuAnimation) {
            showActions = false
            showAppMenu = false
        }
    }

    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: 0.14)

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
    }

    // MARK: - Actions

    private func moveVertically(_ delta: Int) {
        vm.selection = screen.move(delta, axis: .vertical, from: selection)
            ?? PaletteRowIndex(sectionCounts: [screen.rows.count]).moved(
                from: selection, by: delta)
        scroll = ScrollIntent(kind: .follow)
    }

    private func moveHorizontally(_ delta: Int) -> Bool {
        guard let next = screen.move(delta, axis: .horizontal, from: selection) else {
            return false
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
        return true
    }

    /// Move the open menu's highlight, clamped at the ends (no wrap — consistent with `move`).
    private func moveMenu(_ delta: Int) {
        guard let count = menuContent?.items.count, count > 0 else { return }
        menuSelection = min(max(menuSelection + delta, 0), count - 1)
    }

    private func activateMenuItem(_ index: Int) {
        guard let items = menuContent?.items, items.indices.contains(index) else { return }
        items[index].action()
        closeMenus()
    }

    private func toggleMode() {
        vm.mode = vm.mode == .launcher ? .clipboard : .launcher
    }

    private func exitToLauncher() {
        vm.prepare(mode: .launcher)
    }

    private func activateSelection() {
        guard !isCollapsed else { return }
        screen.activate(at: selection)
    }
}

private struct MenuCircleButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 14, height: 1.5)
                Capsule().frame(width: 8, height: 1.5)
            }
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

extension View {
    /// Faint mouse-hover highlight for a palette row, armed only by physical pointer movement.
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        modifier(ArmedHoverModifier(hovered: hovered))
    }
}

private struct ArmedHoverModifier: ViewModifier {
    @Environment(PaletteState.self) private var palette
    let hovered: Binding<Bool>

    func body(content: Content) -> some View {
        content.onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active: hovered.wrappedValue = palette.hoverHighlightArmed
            case .ended: hovered.wrappedValue = false
            }
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
