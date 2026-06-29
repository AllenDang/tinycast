import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selectedID: AppEntry.ID?
    let favoriteCount: Int
    let showSections: Bool
    let onActions: (AppEntry) -> Void
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var runningApps: RunningAppsMonitor

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
                                        running: app.bundleID.map(runningApps.runningBundleIDs.contains) ?? false
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { core.launch(app) }
                                    .onRightClick { onActions(app) }
                                }
                            }
                        }
                        .padding(8)
                    }
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
                            .frame(width: 5, height: 5)
                            .offset(y: 5)
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

/// Actions popover content for a launcher app — shown anchored at the bottom-right on right-click.
struct AppActionsMenu: View {
    let app: AppEntry
    let dismiss: () -> Void
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            actionButton("Open Application", systemImage: "arrow.up.forward.app") {
                core.launch(app)
            }
            if favorites.isFavorite(app) {
                actionButton("Remove from Favorites", systemImage: "star.slash") {
                    favorites.toggle(app)
                }
            } else {
                actionButton("Add to Favorites", systemImage: "star") {
                    favorites.toggle(app)
                }
            }
            actionButton("Show in Finder", systemImage: "folder") {
                core.showInFinder(app)
            }
        }
        .padding(6)
        .frame(width: 220)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
