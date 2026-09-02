import SwiftUI

struct AICommandsSettingsView: View {
    @Environment(AICommandCoordinator.self) private var coordinator
    @Environment(AIProviderStore.self) private var aiProvider
    @Environment(AICommandStore.self) private var store
    @State private var apiKeyDrafts: [UUID: String] = [:]
    @State private var commandEditor: CommandEditorTarget?
    @State private var providerEditor: ProviderEditorTarget?

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
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { aiProvider.isEnabled },
                            set: { wantsOn in
                                if wantsOn {
                                    Task {
                                        if await coordinator.confirmEnablingProvider() {
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

                if !aiProvider.providers.isEmpty {
                    SettingsDivider()
                    ForEach(Array(aiProvider.providers.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 { SettingsDivider() }
                        providerRow(provider)
                    }
                }

                SettingsDivider()
                SettingsRow(
                    title: "Add Provider",
                    subtitle: "Another OpenAI-compatible endpoint — Groq, a local LLM, …",
                    systemImage: "plus.circle",
                    tint: .green
                ) {
                    Button("Add…") { providerEditor = ProviderEditorTarget(provider: nil) }
                        .controlSize(.small)
                }
            }

            commands
        }
        .task {
            for provider in aiProvider.providers where apiKeyDrafts[provider.id] == nil {
                apiKeyDrafts[provider.id] = aiProvider.apiKey(for: provider.id)
            }
        }
        .sheet(item: $commandEditor) { target in
            AICommandEditorSheet(command: target.command)
        }
        .sheet(item: $providerEditor) { target in
            AIProviderEditorSheet(provider: target.provider)
        }
    }

    private var enableSubtitle: String {
        guard aiProvider.isEnabled else {
            return "Off — no endpoint is contacted, and keywords below don't match in the launcher."
        }
        return aiProvider.isConfigured
            ? "Typing a keyword and some text shows a card; ↵ sends it to the configured endpoint."
            : "On, but no provider below has a Base URL, Model and API Key — keywords won't match yet."
    }

    // MARK: - Provider row

    private func providerRow(_ provider: AIProvider) -> some View {
        let configured = aiProvider.isProviderConfigured(provider.id)
        return HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: configured ? "network" : "network.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(configured ? .green : .secondary)
                .frame(width: Theme.Size.settingsRowIcon)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(provider.name)
                        .font(.body)
                        .lineLimit(1)
                    if !configured {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                    }
                }
                Text("\(provider.baseURLString) — \(provider.model)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Theme.Spacing.lg)

            Button(
                action: { providerEditor = ProviderEditorTarget(provider: provider) },
                label: { Image(systemName: "pencil") })
            .buttonStyle(.plain)
            .help("Edit Provider")
            .accessibilityLabel("Edit \(provider.name)")

            Button(
                action: { deleteProvider(provider) },
                label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                })
            .buttonStyle(.plain)
            .help("Delete Provider")
            .accessibilityLabel("Delete \(provider.name)")
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private func deleteProvider(_ provider: AIProvider) {
        aiProvider.removeProvider(id: provider.id)
        apiKeyDrafts.removeValue(forKey: provider.id)
    }

    // MARK: - Commands

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
                        providerName: aiProvider.provider(id: command.providerID ?? UUID())?.name,
                        onEdit: { commandEditor = CommandEditorTarget(command: command) },
                        onDelete: { Task { await coordinator.delete(command) } })
                }
            }
            SettingsDivider()

            SettingsRow(
                title: "Add AI Command",
                subtitle: aiProvider.providers.isEmpty
                    ? "Add a provider above first." : "Give it a keyword, a name, and a prompt using {input}.",
                systemImage: "plus.circle",
                tint: .green
            ) {
                Button("Add…") { commandEditor = CommandEditorTarget(command: nil) }
                    .controlSize(.small)
                    .disabled(aiProvider.providers.isEmpty)
            }
        }
        .opacity(aiProvider.isEnabled ? 1 : 0.45)
        .disabled(!aiProvider.isEnabled)
    }

    private var sortedCommands: [AICommand] {
        store.commands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Editor targets

private struct CommandEditorTarget: Identifiable {
    let id = UUID()
    let command: AICommand?
}

private struct ProviderEditorTarget: Identifiable {
    let id = UUID()
    let provider: AIProvider?
}

// MARK: - Provider editor

/// Add / edit sheet for a single AI provider, presented from the AI Commands pane.
struct AIProviderEditorSheet: View {
    let provider: AIProvider?

    @Environment(\.dismiss) private var dismiss
    @Environment(AIProviderStore.self) private var aiProvider
    @State private var name: String
    @State private var baseURLString: String
    @State private var model: String
    @State private var apiKeyDraft: String
    @State private var errorMessage: String?

    init(provider: AIProvider?) {
        self.provider = provider
        _name = State(initialValue: provider?.name ?? "")
        _baseURLString = State(initialValue: provider?.baseURLString ?? "")
        _model = State(initialValue: provider?.model ?? "")
        _apiKeyDraft = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(provider == nil ? "Add Provider" : "Edit Provider")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Name")
                    .font(.callout.weight(.medium))
                TextField("OpenAI", text: $name)
                    .textFieldStyle(.roundedBorder)
                Text("A display name for this endpoint — shown in the command editor's provider picker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Base URL")
                    .font(.callout.weight(.medium))
                TextField("https://…", text: $baseURLString)
                    .textFieldStyle(.roundedBorder)
                Text("The server's own root — Tinycast posts to {Base URL}/chat/completions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Model")
                    .font(.callout.weight(.medium))
                TextField("gpt-4o-mini", text: $model)
                    .textFieldStyle(.roundedBorder)
                Text("Sent as “model” in every request — whatever the endpoint expects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("API Key")
                    .font(.callout.weight(.medium))
                SecureField("sk-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Text("Stored in the Keychain, never in a settings file or backup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
        .task {
            if let provider, apiKeyDraft.isEmpty {
                apiKeyDraft = aiProvider.apiKey(for: provider.id)
            }
        }
    }

    private func save() {
        let draft = AIProvider(
            id: provider?.id ?? UUID(), name: name, baseURLString: baseURLString, model: model)
        do {
            if provider == nil {
                try aiProvider.addProvider(draft)
            } else {
                try aiProvider.updateProvider(draft)
            }
            aiProvider.setAPIKey(apiKeyDraft, for: draft.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Command row

private struct AICommandSettingsRow: View {
    let command: AICommand
    let providerName: String?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: AICommand.sfSymbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: Theme.Size.settingsRowIcon)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(command.name)
                        .font(.body)
                        .lineLimit(1)
                    if let providerName {
                        Text(providerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Theme.Colors.controlSurface)
                            )
                    }
                }
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
