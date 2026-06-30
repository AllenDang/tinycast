import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selectedID: AppEntry.ID?
    let favoriteCount: Int
    let showSections: Bool
    let onActions: (AppEntry) -> Void
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var runningApps: RunningAppsMonitor
    /// The mouse-hovered row — a layer that's independent of (and visually distinct from) the
    /// keyboard selection, just like Raycast. Hover never moves the selection or scrolls.
    @State private var hoveredID: AppEntry.ID?

    private enum Row: Identifiable {
        case header(String)
        case app(AppEntry)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .app(let app): return app.id
            }
        }
    }

    private var rows: [Row] {
        guard showSections else { return results.map(Row.app) }
        var rows: [Row] = []
        let favorites = results.prefix(favoriteCount)
        let rest = results.dropFirst(favoriteCount)
        if !favorites.isEmpty {
            rows.append(.header("Favorites"))
            rows.append(contentsOf: favorites.map(Row.app))
        }
        if !rest.isEmpty {
            rows.append(.header("Applications"))
            rows.append(contentsOf: rest.map(Row.app))
        }
        return rows
    }

    var body: some View {
        Group {
            if results.isEmpty {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(rows) { row in
                                switch row {
                                case .header(let title):
                                    SectionHeader(title: title)
                                case .app(let app):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedID,
                                        hovered: app.id == hoveredID,
                                        running: app.bundleID.map(runningApps.runningBundleIDs.contains) ?? false
                                    )
                                    .contentShape(Rectangle())
                                    // Only set on enter; clearing happens once at the list level
                                    // (below). A fast sweep is a clean run of enters with no
                                    // transient nil, so the hover layer never flickers.
                                    .onHover { if $0 { hoveredID = app.id } }
                                    .onTapGesture { core.launch(app) }
                                    .onRightClick { onActions(app) }
                                }
                            }
                        }
                        .padding(Theme.Spacing.sm)
                    }
                    // Clear hover only when the cursor leaves the whole list, not between rows.
                    .onHover { inside in if !inside { hoveredID = nil } }
                    .onChange(of: selectedID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Theme.Typography.sectionHeader)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xs / 2)
    }
}

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let hovered: Bool
    let running: Bool

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(selected ? Color.white : Color.secondary)
                            .frame(width: 4, height: 4)
                            .offset(y: 4)
                    }
                }
            Text(app.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.primary)
            Spacer()
            Text("Application")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
    }
}

/// Actions popover content for a launcher app — shown anchored at the bottom-right on right-click
/// or from the Actions pill. Styled like Raycast's actions menu.
struct AppActionsMenu: View {
    let app: AppEntry
    let dismiss: () -> Void
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        PopoverMenu(header: app.name) {
            PopoverMenuRow(title: "Open Application", systemImage: "arrow.up.forward.app", shortcut: "↵") {
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
            PopoverMenuRow(title: "Show in Finder", systemImage: "folder") {
                core.showInFinder(app)
                dismiss()
            }
        }
    }
}
