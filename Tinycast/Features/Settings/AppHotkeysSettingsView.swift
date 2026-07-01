import KeyboardShortcuts
import SwiftUI

struct AppHotkeysSettingsView: View {
    @EnvironmentObject private var appIndex: AppIndex
    @State private var query = ""

    private var filtered: [AppEntry] {
        query.isEmpty ? appIndex.apps : appIndex.matches(query)
    }

    var body: some View {
        // One uniform inset (`xxl`) on every side, and the same value for the gaps between the
        // header, the search field and the list — so vertical rhythm matches the horizontal inset.
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            SettingsHeader(
                title: "App Hotkeys",
                subtitle: "Assign a global shortcut to launch a specific app."
            )

            searchField

            appList
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search apps…", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.body)
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }

    private var appList: some View {
        // Run the matcher once per render, not once per row.
        let apps = filtered
        // A SwiftUI `List` swallows the click that the recorder (an NSSearchField) needs to become
        // first responder, so shortcuts never record. A ScrollView + LazyVStack keeps the rows lazy
        // while letting each recorder take focus on click.
        return ScrollView {
            LazyVStack(spacing: 1) {
                if apps.isEmpty {
                    Text("No apps match “\(query)”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xxl * 2)
                } else {
                    ForEach(apps) { app in
                        AppHotkeyRow(app: app)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .thinOverlayScrollbar()
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

private struct AppHotkeyRow: View {
    let app: AppEntry
    // Hover lives on the row itself so a mouse sweep repaints only the rows entering/leaving.
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 22, height: 22)
            Text(app.name).lineLimit(1)
            Spacer(minLength: Theme.Spacing.xl)
            if let bundleID = app.bundleID {
                KeyboardShortcuts.Recorder(for: .app(bundleID)) { shortcut in
                    AppCore.shared.hotKeys.setBinding(
                        bundleID: bundleID, hasShortcut: shortcut != nil)
                }
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .onHover { hovered = $0 }
    }
}
