import SwiftUI

/// Provider connection (endpoint, model, API key, the master consent switch) plus the command
/// catalog itself. Big enough to earn its own tab rather than folding into Miscellaneous, the way
/// Quicklinks and Snippets each have their own pane instead of sharing Commands'.
struct AICommandsSettingsView: View {
    @Environment(AIProviderStore.self) private var aiProvider
    @Environment(AICommandStore.self) private var store
    @State private var apiKeyDraft = ""
    @State private var editor: EditorTarget?
    @State private var pendingDeletion: AICommand?

    var body: some View {
        @Bindable var aiProvider = aiProvider
        SettingsPane(
            title: "AI Commands",
            subtitle: "Type a keyword and some text in the launcher to run it through your own "
                + "OpenAI-compatible endpoint."
        ) {
            SettingsCard(header: "Provider") {
                SettingsRow(
                    title: "Enable AI Commands",
                    subtitle: enableSubtitle,
                    systemImage: AICommand.sfSymbol,
                    tint: .green,
                    statusDot: aiProvider.isEnabled ? .green : nil
                ) {
                    // Deliberately not bound straight to the setting: flipping it on only asks for
                    // consent, so the switch springs back until the user actually accepts.
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { aiProvider.isEnabled },
                            set: { wantsOn in
                                if wantsOn {
                                    Task {
                                        if await AppCore.shared.confirmEnablingAIProvider() {
                                            aiProvider.setEnabled(true)
                                        }
                                    }
                                } else {
                                    aiProvider.setEnabled(false)
                                }
                            })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Base URL",
                    subtitle: "The server's own root — Tinycast posts to {Base URL}/chat/completions.",
                    systemImage: "network",
                    tint: .gray
                ) {
                    TextField("https://…", text: $aiProvider.baseURLString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Model",
                    subtitle: "Sent as “model” in every request — whatever the endpoint expects.",
                    systemImage: "cpu",
                    tint: .gray
                ) {
                    TextField("gpt-4o-mini", text: $aiProvider.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                SettingsDivider()
                SettingsRow(
                    title: "API Key",
                    subtitle: "Stored in the Keychain, never in a settings file or backup.",
                    systemImage: "key",
                    tint: .gray
                ) {
                    SecureField("sk-…", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onChange(of: apiKeyDraft) { _, newValue in aiProvider.apiKey = newValue }
                }
            }

            commands
        }
        .task { apiKeyDraft = aiProvider.apiKey }
        .sheet(item: $editor) { target in
            AICommandEditorSheet(command: target.command)
        }
        .alert(item: $pendingDeletion) { command in
            Alert(
                title: Text("Delete “\(command.name)”?"),
                message: Text("Its keyword will stop matching in the launcher."),
                primaryButton: .destructive(Text("Delete")) {
                    store.remove(id: command.id)
                },
                secondaryButton: .cancel())
        }
    }

    private var enableSubtitle: String {
        guard aiProvider.isEnabled else {
            return "Off — no endpoint is contacted, and keywords below don't match in the launcher."
        }
        return aiProvider.isConfigured
            ? "Typing a keyword and some text shows a card; ↵ sends it to the endpoint below."
            : "On, but Base URL, Model or API Key below is still missing — keywords won't match yet."
    }

    @ViewBuilder
    private var commands: some View {
        SettingsCard(header: "Commands") {
            if store.commands.isEmpty {
                SettingsRow(
                    title: "No AI commands",
                    subtitle: "Add one to trigger it by typing its keyword in the launcher.",
                    systemImage: AICommand.sfSymbol,
                    tint: .secondary
                ) {
                    EmptyView()
                }
            } else {
                ForEach(Array(sortedCommands.enumerated()), id: \.element.id) { index, command in
                    if index > 0 { SettingsDivider() }
                    AICommandSettingsRow(
                        command: command,
                        onEdit: { editor = EditorTarget(command: command) },
                        onDelete: { pendingDeletion = command })
                }
            }
            SettingsDivider()

            SettingsRow(
                title: "Add AI Command",
                subtitle: "Give it a keyword, a name, and a prompt using {input}.",
                systemImage: "plus.circle",
                tint: .green
            ) {
                Button("Add…") { editor = EditorTarget(command: nil) }
                    .controlSize(.small)
            }
        }
        // Same dim as the custom-commands card: the switch above stays live either way.
        .opacity(aiProvider.isEnabled ? 1 : 0.45)
        .disabled(!aiProvider.isEnabled)
    }

    private var sortedCommands: [AICommand] {
        store.commands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private struct EditorTarget: Identifiable {
    let id = UUID()
    let command: AICommand?
}

private struct AICommandSettingsRow: View {
    let command: AICommand
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: AICommand.sfSymbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: Theme.Size.settingsRowIcon)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(command.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(command.keyword) → \(command.promptTemplate)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(command.promptTemplate)
            }

            Spacer(minLength: Theme.Spacing.lg)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Command")
            .accessibilityLabel("Edit \(command.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Command")
            .accessibilityLabel("Delete \(command.name)")
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}
