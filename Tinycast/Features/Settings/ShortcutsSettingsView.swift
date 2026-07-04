import SwiftUI

/// Settings → Shortcuts: everything the launcher can open, grouped by category. Each category has
/// a switch that hides the whole group from the launcher; each row has a visibility checkbox and a
/// hotkey recorder. This tab never applies the visibility filter itself — hidden rows must stay
/// visible here so they can be re-checked.
struct ShortcutsSettingsView: View {
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var visibility: VisibilityStore
    @State private var query = ""

    private var filtered: [AppEntry] {
        query.isEmpty ? appIndex.apps : appIndex.matches(query)
    }

    var body: some View {
        // Same insets as `SettingsPane`: ignore the transparent-titlebar safe area and use one
        // fixed `xxl` inset on every side.
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            SettingsHeader(
                title: "Shortcuts",
                subtitle: "Choose what appears in the launcher and assign global shortcuts."
            )

            searchField

            sectionList
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
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

    private var sectionList: some View {
        // Run the matcher once per render, not once per row.
        let entries = filtered
        let apps = entries.filter { $0.kind == .application }
        let panes = entries.filter { $0.kind == .systemSettings }
        // Each category is its own independently scrollable card; they split the remaining
        // height between them. When a search empties one category, the other takes the space.
        return VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if entries.isEmpty {
                Text("No apps match “\(query)”.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xxl * 2)
            } else {
                if !apps.isEmpty {
                    CategorySection(title: "Applications", kind: .application, entries: apps)
                }
                if !panes.isEmpty {
                    CategorySection(
                        title: "System Settings", kind: .systemSettings, entries: panes)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// One category card: a header row with the section title and the "show this category in the
/// launcher" switch, then the item rows. Rows dim when the category is off but stay interactive.
private struct CategorySection: View {
    let title: String
    let kind: AppEntry.Kind
    let entries: [AppEntry]
    @EnvironmentObject private var visibility: VisibilityStore

    var body: some View {
        let kindVisible = visibility.isKindVisible(kind)
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(title)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: kindBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, Theme.Spacing.xs)

            // Native scroller kept (unlike the palette's overlay list) — this is a plain
            // windowed settings list.
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(entries) { entry in
                        ShortcutRow(entry: entry)
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
            )
            .opacity(kindVisible ? 1 : 0.45)
        }
    }

    private var kindBinding: Binding<Bool> {
        Binding(
            get: { visibility.isKindVisible(kind) },
            set: { visibility.setKindVisible($0, for: kind) }
        )
    }
}

private struct ShortcutRow: View {
    let entry: AppEntry
    @EnvironmentObject private var visibility: VisibilityStore
    // Hover lives on the row itself so a mouse sweep repaints only the rows entering/leaving.
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: entry.icon)
                .resizable()
                .frame(width: 22, height: 22)
            Text(entry.name).lineLimit(1)
            Spacer(minLength: Theme.Spacing.xl)
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
            Toggle("", isOn: itemBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .onHover { hovered = $0 }
    }

    private var itemBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
        )
    }
}
