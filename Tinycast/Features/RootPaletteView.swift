import SwiftUI

struct RootPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var favorites: FavoritesStore
    @FocusState private var searchFocused: Bool
    @State private var showActions = false

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

        return VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            content(apps: apps, clips: clips, selection: sel,
                    favoriteCount: favoriteCount, showSections: showSections)
            Divider().opacity(0.35)
            bottomBar(selectedApp: selectedApp)
        }
        .frame(width: 720, height: 470)
        .background(OverlayScrollers())
        .background(Color.black.opacity(0.25))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: vm.focusToken) { searchFocused = true }
        .onChange(of: vm.query) { vm.selection = 0 }
        .onChange(of: vm.mode) { vm.selection = 0; showActions = false }
        .onAppear { searchFocused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { core.hidePalette(); return .handled }
        .onKeyPress(.tab) { toggleMode(); return .handled }
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            guard vm.mode == .clipboard, press.modifiers.contains(.command) else { return .ignored }
            deleteSelectedClip()
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: vm.mode.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField(vm.mode.placeholder, text: $vm.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($searchFocused)
                .onSubmit(activateSelection)
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
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
                    showActions = true
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
                .frame(width: 290)
                Divider().opacity(0.35)
                ClipboardPreview(item: selected)
            }
        }
    }

    private func bottomBar(selectedApp: AppEntry?) -> some View {
        HStack(spacing: 0) {
            Menu {
                Button("Settings…") { core.showSettings() }
                    .keyboardShortcut(",")
                Button("About Tinycast") { core.showAbout() }
                Button("Changelog") { core.showChangelog() }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            HStack(spacing: 6) {
                Text(vm.mode == .launcher ? "Open Application" : "Paste")
                Image(systemName: "return")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .popover(isPresented: $showActions, arrowEdge: .top) {
                if let app = selectedApp {
                    AppActionsMenu(app: app) { showActions = false }
                        .environmentObject(core)
                        .environmentObject(favorites)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
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
            Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
