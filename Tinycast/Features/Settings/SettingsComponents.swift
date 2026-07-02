import SwiftUI

/// Reusable building blocks for the Settings window. All metrics come from `Theme` so Settings
/// shares one spacing/radius/color vocabulary with the palette.

// MARK: - Pane scaffold

/// Standard layout for a settings pane: a large title + subtitle header, then scrollable content.
/// Every pane uses this so headers, insets and scroll behaviour stay identical across the app.
struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                SettingsHeader(title: title, subtitle: subtitle)
                content
            }
            // Uniform inset on every side — the visible padding matches horizontally and vertically.
            // (The titlebar clearance is handled by the ScrollView's safe area, not by extra padding.)
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hideNativeScrollers()
        }
        .thinScrollbar()
    }
}

/// The title + subtitle block at the top of every pane.
struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Grouped card

/// A rounded, hairline-bordered container that groups related rows — the macOS System Settings
/// "card". Rows are separated by inset dividers via `SettingsRow`/`SettingsDivider`.
struct SettingsCard<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let header {
                Text(header)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Theme.Spacing.xs)
            }
            VStack(spacing: 0) { content }
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
}

/// Inset divider between rows inside a `SettingsCard`, aligned under the row's title (past the icon).
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.cardStroke)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.xl + Theme.Size.settingsRowIcon + Theme.Spacing.lg)
    }
}

// MARK: - Row

/// A single settings line: optional SF Symbol, a title with optional subtitle, and a trailing
/// control. Fixed vertical rhythm keeps every card looking aligned regardless of the control.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: Theme.Size.settingsRowIcon)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.xl)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}
