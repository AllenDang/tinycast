import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var hyperTap = AppCore.shared.hyperKeyTap
    // Same UserDefaults key the `App` binds its `MenuBarExtra(isInserted:)` to — toggling here
    // updates the menu-bar icon live, with no shared observable object between them.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    /// The Hyper modifier chord as prose glyphs, tracking the Include Shift toggle.
    private var hyperGlyphs: String { settings.hyperKeyIncludesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘" }

    private var hyperStatusDot: Color? {
        switch hyperTap.status {
        case .off: return nil
        case .active: return .green
        case .needsAccessibility: return .orange
        }
    }

    private var hyperSubtitle: String {
        guard settings.hyperKey != .none else {
            return
                "Select a physical key to remap to the \(hyperGlyphs) modifier keys simultaneously."
        }
        var text =
            "Pressing \(settings.hyperKey.title) will trigger the left \(hyperGlyphs) modifier keys."
        if settings.hyperKeyReplacesGlyph {
            text += " Hyper Key shortcuts will be shown in Tinycast with ✦."
        }
        if hyperTap.status == .needsAccessibility {
            text += " Tinycast needs Accessibility access to remap keys."
        }
        return text
    }

    var body: some View {
        SettingsPane(
            title: "General",
            subtitle: "Global shortcuts and startup behaviour."
        ) {
            SettingsCard(header: "Global Shortcuts") {
                SettingsRow(
                    title: "App Launcher",
                    subtitle: "Summon the fuzzy app launcher.",
                    systemImage: "magnifyingglass",
                    tint: .blue
                ) {
                    ShortcutRecorder(action: .togglePalette)
                }
            }

            SettingsCard(header: "Hyper Key") {
                SettingsRow(
                    title: "Hyper Key",
                    subtitle: hyperSubtitle,
                    systemImage: "sparkle",
                    tint: .purple,
                    statusDot: hyperStatusDot
                ) {
                    if hyperTap.status == .needsAccessibility {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                    HyperKeyDropdown(selection: $settings.hyperKey)
                        .onChange(of: settings.hyperKey) { _, newKey in
                            // A Quick Press choice is meaningless for a different key.
                            settings.hyperKeyQuickPress = .none
                            if newKey != .none { Permissions.ensureAccessibility() }
                        }
                }
                if settings.hyperKey.hasOriginalFunction {
                    SettingsDivider()
                    SettingsRow(
                        title: "Quick Press",
                        subtitle:
                            "Select an action to perform when \(settings.hyperKey.title) is pressed without any other keys.",
                        systemImage: "hand.tap",
                        tint: .teal
                    ) {
                        Picker("", selection: $settings.hyperKeyQuickPress) {
                            Text("Does Nothing").tag(HyperKeyQuickPress.none)
                            if let original = settings.hyperKey.quickPressOriginalTitle {
                                Text(original).tag(HyperKeyQuickPress.originalKey)
                            }
                            Text("Trigger Escape").tag(HyperKeyQuickPress.escape)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "Include Shift (⇧)",
                    subtitle: "Hyper Key will remap to the \(hyperGlyphs) modifier keys.",
                    systemImage: "shift",
                    tint: .indigo
                ) {
                    Toggle("", isOn: $settings.hyperKeyIncludesShift)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Replace occurrences of \(hyperGlyphs) with ✦",
                    subtitle: "Shortcuts containing the Hyper Key modifiers are shown with ✦.",
                    systemImage: "keyboard",
                    tint: .gray
                ) {
                    Toggle("", isOn: $settings.hyperKeyReplacesGlyph)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "General") {
                SettingsRow(
                    title: "Launch at login",
                    subtitle: "Start Tinycast automatically when you log in.",
                    systemImage: "power",
                    tint: .green
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Show in menu bar",
                    subtitle:
                        "Keep the Tinycast icon in the menu bar. Shortcuts still work when hidden.",
                    systemImage: "menubar.arrow.up.rectangle",
                    tint: .gray
                ) {
                    Toggle("", isOn: $showInMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }
}

/// The key chooser: a pull-down opening a height-capped, scrollable list — a native menu can't
/// cap its height, and 29 flat items fill the screen. Rows follow the app's menu grammar (hover
/// fill, leading checkmark); the list keeps the native scroller.
private struct HyperKeyDropdown: View {
    @Binding var selection: HyperKeyPhysicalKey
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(selection.title)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(HyperKeyPhysicalKey.allCases) { key in
                            HyperKeyDropdownRow(key: key, selected: key == selection) {
                                selection = key
                                isOpen = false
                            }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
                .frame(width: 220, height: 300)
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }
}

private struct HyperKeyDropdownRow: View {
    let key: HyperKeyPhysicalKey
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(selected ? 1 : 0)
                Text(key.title)
                    .font(Theme.Typography.menuRow)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(hovered ? Theme.Colors.menuHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .id(key)
    }
}
