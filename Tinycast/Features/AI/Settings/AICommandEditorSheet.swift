import SwiftUI

/// Add / edit sheet for a single AI command, presented from the AI Commands pane.
struct AICommandEditorSheet: View {
    let command: AICommand?

    private struct ModelSelection: Hashable {
        let providerID: UUID
        let model: String
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AICommandStore.self) private var store
    @Environment(AIProviderStore.self) private var aiProvider
    @State private var keyword: String
    @State private var name: String
    @State private var promptTemplate: String
    @State private var providerID: UUID?
    @State private var model: String?
    @State private var errorMessage: String?

    init(command: AICommand?) {
        self.command = command
        _keyword = State(initialValue: command?.keyword ?? "")
        _name = State(initialValue: command?.name ?? "")
        _promptTemplate = State(initialValue: command?.promptTemplate ?? "")
        _providerID = State(initialValue: command?.providerID)
        _model = State(initialValue: command?.model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(command == nil ? "Add AI Command" : "Edit AI Command")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Model")
                    .font(.callout.weight(.medium))
                Picker("Model", selection: modelSelectionBinding) {
                    Text("Select a model").tag(nil as ModelSelection?)
                    ForEach(aiProvider.providers) { provider in
                        ForEach(provider.models, id: \.self) { model in
                            Text("\(provider.name) / \(model)")
                                .tag(ModelSelection(providerID: provider.id, model: model) as ModelSelection?)
                        }
                    }
                    if let modelSelection, selectedProvider?.resolvedModel(modelSelection.model) == nil {
                        Text("\(selectedProvider?.name ?? "Unavailable provider") / \(modelSelection.model) (Unavailable)")
                            .tag(modelSelection as ModelSelection?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                if aiProvider.providers.isEmpty {
                    Text("Add a provider and its models above first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Keyword")
                    .font(.callout.weight(.medium))
                TextField("trans", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                Text("Typed as the first word, followed by a space and the text to act on — “trans hello”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Name")
                    .font(.callout.weight(.medium))
                TextField("Translate", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Prompt")
                    .font(.callout.weight(.medium))
                TextEditor(text: $promptTemplate)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.sm)
                    .frame(height: Theme.Size.editorTextHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            }

            Text("Use {input} for the typed text. Example: Translate this to English: {input}")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

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
                        keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || selectedProvider?.resolvedModel(model) == nil)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
    }

    private var selectedProvider: AIProvider? {
        guard let providerID else { return nil }
        return aiProvider.provider(id: providerID)
    }

    private var modelSelection: ModelSelection? {
        guard let providerID, let model = model ?? selectedProvider?.models.first else { return nil }
        return ModelSelection(providerID: providerID, model: model)
    }

    private var modelSelectionBinding: Binding<ModelSelection?> {
        Binding(
            get: { modelSelection },
            set: { selection in
                providerID = selection?.providerID
                model = selection?.model
            })
    }

    private func save() {
        guard let model = selectedProvider?.resolvedModel(model) else { return }
        let draft = AICommand(
            id: command?.id ?? UUID(), keyword: keyword, name: name, promptTemplate: promptTemplate,
            providerID: providerID, model: model)
        do {
            if command == nil {
                try store.add(draft)
            } else {
                try store.update(draft)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
