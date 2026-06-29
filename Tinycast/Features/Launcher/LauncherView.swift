import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selectedID: AppEntry.ID?
    let favoriteCount: Int
    let showSections: Bool
    let onActions: (AppEntry) -> Void
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var runningApps: RunningAppsMonitor
    /// Mouse hover wins the highlight; when the cursor leaves the list we fall back to the
    /// keyboard selection. Kept separate from `vm.selection` so hovering never triggers auto-scroll.
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
                                        selected: hoveredID == nil ? app.id == selectedID : hoveredID == app.id,
                                        running: app.bundleID.map(runningApps.runningBundleIDs.contains) ?? false
                                    )
                                    .contentShape(Rectangle())
                                    .onHover { inside in
                                        if inside { hoveredID = app.id }
                                        else if hoveredID == app.id { hoveredID = nil }
                                    }
                                    .onTapGesture { core.launch(app) }
                                    .onRightClick { onActions(app) }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedID) { _, id in
                        hoveredID = nil
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let running: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 22, height: 22)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 4, height: 4)
                            .offset(y: 4)
                    }
                }
            Text(app.name)
                .font(.system(size: 14))
                .lineLimit(1)
            Spacer()
            Text("Application")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.1) : Color.clear)
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
