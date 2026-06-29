import SwiftUI

struct RootPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var store: ClipboardStore
    @FocusState private var searchFocused: Bool

    private var appResults: [AppEntry] { appIndex.matches(vm.query) }
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

        return VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            content(apps: apps, clips: clips, selection: sel)
        }
        .frame(width: 720, height: 470)
        .background(OverlayScrollers())
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: vm.focusToken) { searchFocused = true }
        .onChange(of: vm.query) { vm.selection = 0 }
        .onChange(of: vm.mode) { vm.selection = 0 }
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
            modePicker
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
    }

    private var modePicker: some View {
        Picker("", selection: $vm.mode) {
            ForEach(PaletteMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 170)
    }

    @ViewBuilder
    private func content(apps: [AppEntry], clips: [ClipboardItem], selection: Int) -> some View {
        switch vm.mode {
        case .launcher:
            let selectedID = apps.indices.contains(selection) ? apps[selection].id : nil
            LauncherList(results: apps, selectedID: selectedID)
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
