import SwiftUI

struct RootPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var favorites: FavoritesStore
    @FocusState private var searchFocused: Bool
    @State private var showActions = false
    @State private var showAppMenu = false

    private var isQueryEmpty: Bool { vm.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Ordered launcher results — the single source of truth for the list, selection and activation.
    /// Empty query pins favorites to the top; otherwise plain ranked matches.
    private var appResults: [AppEntry] {
        let base = appIndex.matches(vm.query)
        guard isQueryEmpty, !favorites.keys.isEmpty else { return base }
        let split = favorites.ordered(base)
        return split.favorites + split.rest
    }
    private var clipResults: [ClipboardItem] { store.search(vm.query) }
    private var resultCount: Int { vm.mode == .launcher ? appResults.count : clipResults.count }
    /// Selection clamped into the current results — the single source of truth for highlight,
    /// preview and activation so the list and preview can never disagree.
    private var selection: Int { resultCount == 0 ? 0 : min(max(vm.selection, 0), resultCount - 1) }

    var body: some View {
        // Filter once per render for the active mode only; event handlers (rare) use the computed
        // properties above. Avoids running the matcher/search several times for a single render.
        let apps = vm.mode == .launcher ? appResults : []
        let clips = vm.mode == .clipboard ? clipResults : []
        let count = vm.mode == .launcher ? apps.count : clips.count
        let sel = count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
        let showSections = vm.mode == .launcher && isQueryEmpty && !favorites.keys.isEmpty
        let favoriteCount = showSections ? apps.prefix(while: { favorites.isFavorite($0) }).count : 0
        let selectedApp = apps.indices.contains(sel) ? apps[sel] : nil

        // The results layer fills the whole panel; the search header and action bar float on top
        // as translucent Liquid Glass bars (via safeAreaInset). The list scrolls *behind* them and
        // stays faintly visible through the glass — the Raycast look, with no hard dividers.
        return content(apps: apps, clips: clips, selection: sel,
                       favoriteCount: favoriteCount, showSections: showSections)
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
            if showActions, let app = selectedApp {
                AppActionsMenu(app: app) { closeMenus() }
                    .environmentObject(core)
                    .environmentObject(favorites)
                    .padding(Self.menuInset)
                    .transition(Self.menuTransition(.bottomTrailing))
            }
        }
        .frame(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight)
        // A subtle dark wash over the vibrancy deepens the surface to match Raycast (the app is
        // always dark, so this only darkens — it never muddies a light material).
        .background(Color.black.opacity(0.50))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .onChange(of: vm.focusToken) { searchFocused = true }
        .onChange(of: vm.query) { vm.selection = 0 }
        .onChange(of: vm.mode) { vm.selection = 0; showActions = false }
        .onAppear { searchFocused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) {
            if showActions || showAppMenu { closeMenus(); return .handled }
            core.hidePalette(); return .handled
        }
        .onKeyPress(.tab) { toggleMode(); return .handled }
        .onKeyPress(keys: [","], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            core.showSettings()
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            guard vm.mode == .clipboard, press.modifiers.contains(.command) else { return .ignored }
            deleteSelectedClip()
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: vm.mode.systemImage)
                .font(Theme.Typography.headerIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            TextField(vm.mode.placeholder, text: $vm.query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.searchField)
                .focused($searchFocused)
                .onSubmit(activateSelection)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .frame(height: Theme.Size.headerHeight)
        .frame(maxWidth: .infinity)
        .background(EdgeFade(edge: .top))
    }

    @ViewBuilder
    private func content(apps: [AppEntry], clips: [ClipboardItem], selection: Int,
                         favoriteCount: Int, showSections: Bool) -> some View {
        switch vm.mode {
        case .launcher:
            let selectedID = apps.indices.contains(selection) ? apps[selection].id : nil
            LauncherList(
                results: apps,
                selectedID: selectedID,
                favoriteCount: favoriteCount,
                showSections: showSections,
                onActions: { app in
                    if let index = apps.firstIndex(of: app) { vm.selection = index }
                    withAnimation(Self.menuAnimation) { showActions = true }
                }
            )
        case .clipboard:
            let selected = clips.indices.contains(selection) ? clips[selection] : nil
            HStack(spacing: 0) {
                ClipboardList(
                    results: clips,
                    selectedID: selected?.id,
                    onSelect: { item in vm.selection = clips.firstIndex(of: item) ?? 0 },
                    onActivate: activateSelection
                )
                .frame(width: Theme.Size.clipboardListWidth)
                ClipboardPreview(item: selected)
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
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
        .background(EdgeFade(edge: .bottom))
    }

    private var appMenuButton: some View {
        Button { withAnimation(Self.menuAnimation) { showAppMenu.toggle() } } label: {
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
            PopoverMenuRow(title: "Settings…", systemImage: "gearshape", shortcut: "⌘,") {
                closeMenus(); core.showSettings()
            }
            PopoverMenuRow(title: "About Tinycast", systemImage: "info.circle") {
                closeMenus(); core.showAbout()
            }
            PopoverMenuRow(title: "Changelog", systemImage: "doc.text") {
                closeMenus(); core.showChangelog()
            }
        }
    }

    private var actionPill: some View {
        Button(action: activateSelection) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(vm.mode == .launcher ? "Open Application" : "Paste")
                Image(systemName: "return")
            }
            .font(Theme.Typography.pill)
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .frosted(in: Capsule())
    }

    private func closeMenus() {
        withAnimation(Self.menuAnimation) { showActions = false; showAppMenu = false }
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

    // MARK: - Actions

    private func move(_ delta: Int) {
        guard resultCount > 0 else { return }
        vm.selection = min(max(selection + delta, 0), resultCount - 1)
    }

    private func toggleMode() {
        vm.mode = vm.mode == .launcher ? .clipboard : .launcher
    }

    private func activateSelection() {
        switch vm.mode {
        case .launcher:
            guard appResults.indices.contains(selection) else { return }
            core.launch(appResults[selection])
        case .clipboard:
            guard clipResults.indices.contains(selection) else { return }
            core.paste(clipResults[selection])
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

/// The Raycast-style scroll-edge treatment for the floating header/footer: a translucent blur
/// that's strongest right at the panel edge — so the list scrolling underneath the search field
/// and the action buttons goes soft and dim, never colliding with them — then fades smoothly to
/// nothing toward the middle of the list. No hard edge, no bar.
private struct EdgeFade: View {
    let edge: VerticalEdge

    var body: some View {
        let start: UnitPoint = edge == .top ? .top : .bottom
        let end: UnitPoint = edge == .top ? .bottom : .top
        // Hold full strength near the edge, then fade out — this is what removes the hard line.
        let fade = LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.4),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: start, endPoint: end
        )
        // Just the edge blur — no darkening wash. Where no rows sit behind it, the blurred
        // material resolves to the window background and disappears; only content scrolling under
        // the edge goes soft. That's why Raycast's edge is invisible at rest.
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(fade)
    }
}
