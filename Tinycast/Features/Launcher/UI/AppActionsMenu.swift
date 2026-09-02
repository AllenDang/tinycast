import SwiftUI

@MainActor
enum AppActionsMenu {
    static func content(
        app: AppEntry, searchQuery: String, launcher: LauncherCoordinator,
        favorites: FavoritesStore, running: Bool, onResetRanking: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: app.kind.descriptor.openVerb, systemImage: "list.bullet.rectangle",
                shortcut: "↵"
            ) { launcher.launch(app, searchQuery: searchQuery) }
        ]
        if favorites.isFavorite(app) {
            items.append(
                PopoverMenuItem(title: "Remove from Favorites", systemImage: "star.slash") {
                    favorites.toggle(app)
                })
        } else {
            items.append(
                PopoverMenuItem(title: "Add to Favorites", systemImage: "star") {
                    favorites.toggle(app)
                })
        }
        if launcher.hasRanking(for: app) {
            items.append(
                PopoverMenuItem(title: "Reset Ranking", systemImage: "arrow.counterclockwise") {
                    onResetRanking()
                })
        }
        if app.canRevealInFinder {
            items.append(
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵"
                ) {
                    launcher.showInFinder(app)
                })
        }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Quit Application", systemImage: "power", shortcut: "⌃⇧Q",
                    isDestructive: true
                ) {
                    launcher.quit(app)
                })
        }
        if app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall Application", systemImage: "trash", isDestructive: true
                ) {
                    launcher.beginUninstall(app)
                })
        }
        return PopoverMenuContent(header: app.name, items: items)
    }
}
