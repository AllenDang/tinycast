import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selectedID: AppEntry.ID?
    let favoriteCount: Int
    let showSections: Bool
    /// Changes only when the list should scroll to follow the selection (keyboard nav / reset), so
    /// mouse selection never yanks the scroll position.
    let scrollToken: UUID
    /// Inline calculator answer for the current query; occupies flat selection index 0 when
    /// present (calc requires a non-empty query, so it never coexists with the sectioned view).
    var calc: CalcResult?
    var calcSelected = false
    var onActivateCalc: () -> Void = {}
    var onCalcActions: () -> Void = {}
    let onActions: (AppEntry) -> Void
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var runningApps: RunningAppsMonitor

    private nonisolated static let calcRowID = "calc-card"

    private enum Row: Identifiable {
        case header(String)
        case calc(CalcResult)
        case app(AppEntry)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .calc: return LauncherList.calcRowID
            case .app(let app): return app.id
            }
        }
    }

    private var rows: [Row] {
        var calcRows: [Row] = []
        if let calc { calcRows = [.header("Calculator"), .calc(calc)] }
        guard showSections else { return calcRows + results.map(Row.app) }
        var rows: [Row] = calcRows
        let favorites = results.prefix(favoriteCount)
        let rest = results.dropFirst(favoriteCount)
        // `rest` is apps-then-panes-then-commands by the AppIndex sort invariant, so filtering by
        // kind keeps row order identical to `results` order and the flat selection index stays valid.
        let apps = rest.filter { $0.kind == .application }
        let panes = rest.filter { $0.kind == .systemSettings }
        let commands = rest.filter { $0.kind == .command }
        for (title, group) in [
            ("Favorites", Array(favorites)), ("Applications", apps),
            ("System Settings", panes), ("Commands", commands),
        ]
        where !group.isEmpty {
            rows.append(.header(title))
            rows.append(contentsOf: group.map(Row.app))
        }
        return rows
    }

    var body: some View {
        Group {
            if results.isEmpty && calc == nil {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(rows) { row in
                                switch row {
                                case .header(let title):
                                    SectionHeader(title: title)
                                case .calc(let result):
                                    CalculatorCard(result: result, selected: calcSelected)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateCalc)
                                        .onRightClick(perform: onCalcActions)
                                        .padding(.bottom, Theme.Spacing.xs)
                                case .app(let app):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedID,
                                        running: app.bundleID.map(
                                            runningApps.runningBundleIDs.contains) ?? false
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { core.launch(app) }
                                    .onRightClick { onActions(app) }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.xs)
                        .padding(.bottom, Theme.Spacing.md)
                        .hideNativeScrollers()
                    }
                    .edgeDissolve()
                    .thinScrollbar()
                    .onChange(of: scrollToken) {
                        if calcSelected {
                            proxy.scrollTo(Self.calcRowID, anchor: .center)
                        } else if let selectedID {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

/// Section label above a group of rows, shared by the launcher and clipboard so both lists use one identical header + row layout.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xs / 2)
    }
}

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let running: Bool
    /// Hover lives on the row itself, so moving the mouse repaints only the rows entering/leaving —
    /// it never invalidates the parent list body (which would rebuild every row on each sweep).
    @State private var hovered = false
    /// Observed so a hotkey set/cleared in Settings re-renders the row and updates its keycaps
    /// immediately — the persisted palette tree wouldn't otherwise re-read the shortcut.
    @EnvironmentObject private var hotKeys: HotKeyManager

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// Keycaps for this entry's hotkey, or `nil` if none is bound.
    private var shortcutCaps: [String]? {
        guard let action = app.hotKeyAction,
            let shortcut = hotKeys.shortcut(for: action)
        else { return nil }
        return shortcut.keycaps
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 4, height: 4)
                            .offset(y: 4)
                    }
                }
            Text(app.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            if let caps = shortcutCaps {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCap(text: cap)
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
        .onHover { hovered = $0 }
    }
}

/// A single keycap (one modifier symbol or the key) shown next to an app with a bound hotkey.
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.keyCap)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
            )
    }
}

/// Actions popover content for a launcher app, anchored at the bottom-right on right-click or from the Actions pill.
struct AppActionsMenu: View {
    let app: AppEntry
    let dismiss: () -> Void
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var favorites: FavoritesStore

    private var openTitle: String {
        switch app.kind {
        case .application: return "Open Application"
        case .systemSettings: return "Open"
        case .command: return "Run Command"
        }
    }

    var body: some View {
        PopoverMenu(header: app.name) {
            PopoverMenuRow(
                title: openTitle,
                systemImage: "list.bullet.rectangle", shortcut: "↵"
            ) {
                core.launch(app)
                dismiss()
            }
            if favorites.isFavorite(app) {
                PopoverMenuRow(title: "Remove from Favorites", systemImage: "star.slash") {
                    favorites.toggle(app)
                    dismiss()
                }
            } else {
                PopoverMenuRow(title: "Add to Favorites", systemImage: "star") {
                    favorites.toggle(app)
                    dismiss()
                }
            }
            if app.kind != .command {
                PopoverMenuRow(title: "Show in Finder", systemImage: "folder") {
                    core.showInFinder(app)
                    dismiss()
                }
            }
        }
    }
}
