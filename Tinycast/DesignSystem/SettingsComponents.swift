import SwiftUI

// Shared settings surfaces use the same card hierarchy.

// MARK: - Pane scaffold

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
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlayScroller()
        }
        .ignoresSafeArea(edges: .top)
        .shortcutRecorderPopoverHost()
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

struct SettingsCard<Content: View>: View {
    var header: String?
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

struct FeatureSwitchCard: View {
    let header: String
    let enableTitle: String
    let enableSubtitle: String
    let systemImage: String
    let launcherSubtitle: String
    @Binding var isEnabled: Bool
    @Binding var showsInLauncher: Bool

    var body: some View {
        SettingsCard(header: header) {
            SettingsRow(
                title: enableTitle,
                subtitle: enableSubtitle,
                systemImage: systemImage,
                tint: .green
            ) {
                Toggle(enableTitle, isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(enableTitle)
            }
            SettingsDivider()
            SettingsRow(
                title: "Show in launcher",
                subtitle: launcherSubtitle,
                systemImage: "magnifyingglass",
                tint: .green
            ) {
                Toggle("Show in launcher", isOn: $showsInLauncher)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Show in launcher")
            }
            // Same dim as ShortcutsSettingsView's hidden-category card.
            .opacity(isEnabled ? 1 : 0.45)
            .disabled(!isEnabled)
        }
    }
}

struct SettingsSearchField: View {
    let prompt: String
    @Binding var query: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
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
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.cardStroke)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.xl + Theme.Size.settingsRowIcon + Theme.Spacing.lg)
    }
}

// MARK: - Row

struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var tint: Color = .secondary
    /// Optional state indicator rendered after the title (green = active, orange = attention).
    var statusDot: Color?
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
                HStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(.body)
                    if let statusDot {
                        Circle()
                            .fill(statusDot)
                            .frame(width: Theme.Size.statusDot, height: Theme.Size.statusDot)
                    }
                }
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

// MARK: - Callout

struct SettingsCallout<Trailing: View>: View {
    let title: String
    var message: String?
    var systemImage: String = "info.circle"
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: Theme.Size.settingsRowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(title).font(.body)
                if let message {
                    Text(message)
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
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

extension SettingsCallout where Trailing == EmptyView {
    init(title: String, message: String? = nil, systemImage: String = "info.circle", tint: Color = .secondary) {
        self.init(title: title, message: message, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}
