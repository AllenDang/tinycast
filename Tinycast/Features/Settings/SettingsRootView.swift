import SwiftUI

extension Notification.Name {
    static let tinycastShowSettings = Notification.Name("TinycastShowSettings")
}

private enum SettingsTab: Int, CaseIterable, Identifiable {
    case general, clipboard, permissions, appShortcuts
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .clipboard: return "Clipboard"
        case .permissions: return "Permissions"
        case .appShortcuts: return "App Shortcuts"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .clipboard: return "doc.on.clipboard"
        case .permissions: return "lock.shield"
        case .appShortcuts: return "keyboard"
        }
    }

    /// Colored icon tile, System Settings style — a small cue that makes the sidebar scannable.
    var tint: Color {
        switch self {
        case .general: return .gray
        case .clipboard: return .orange
        case .permissions: return .blue
        case .appShortcuts: return .indigo
        }
    }
}

struct SettingsRootView: View {
    @State private var tab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            // A plain conditional swap — not a `TabView`. macOS's TabView is backed by `NSTabView`,
            // which re-hosts each tab's view on selection; that re-hosting is the visible flicker and
            // it also tears down the hotkey `Recorder`'s window membership mid-interaction (so the
            // first recording attempt fails). Switching content this way keeps each pane's hosting
            // view stable, fixing both.
            Group {
                switch tab {
                case .general: GeneralSettingsView()
                case .clipboard: ClipboardSettingsView()
                case .permissions: PermissionsSettingsView()
                case .appShortcuts: AppShortcutsSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Only the *background* bleeds to every window edge (under the titlebar, down to the
            // bottom corners). The pane content keeps the safe area, so it lays out below the
            // transparent titlebar automatically — no manual titlebar spacer, no exposed dark bar.
            .background(
                VisualEffectView(material: .contentBackground, blending: .behindWindow)
                    .ignoresSafeArea()
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .tinycastShowSettings)) { _ in
            tab = .general
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
            ForEach(SettingsTab.allCases) { item in
                SidebarRow(
                    title: item.title,
                    systemImage: item.systemImage,
                    tint: item.tint,
                    isSelected: tab == item
                ) { tab = item }
            }

            Spacer()
        }
        .padding(.top, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(width: Theme.Size.settingsSidebar)
        .frame(maxHeight: .infinity)
        // Bleed the sidebar material to every edge (up under the traffic lights, down to the bottom
        // corners) so it reads as one continuous surface behind the safe-area content. The trailing
        // hairline lives in the same edge-to-edge background — a plain `Divider` in the HStack would
        // stop at the safe area, leaving the titlebar band without a seam.
        .background(
            ZStack(alignment: .trailing) {
                VisualEffectView(material: .sidebar, blending: .behindWindow)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            }
            .ignoresSafeArea()
        )
    }
}

/// One sidebar entry: a colored icon tile + label, with an accent highlight when selected and a
/// subtle hover state otherwise.
private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                Text(title)
                    .font(Theme.Typography.rowTitle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    // Match the launcher list: a soft neutral selection fill (not a saturated accent block), with a
    // fainter hover layer.
    private var background: Color {
        if isSelected { return Theme.Colors.selection }
        if hovering { return Theme.Colors.rowHover }
        return .clear
    }
}
