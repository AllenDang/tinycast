import SwiftUI

/// Add / edit sheet for a single AI command, presented from the AI Commands pane.
struct AICommandEditorSheet: View {
    let command: AICommand?

    @Environment(\.dismiss) private var dismiss
    @Environment(AICommandStore.self) private var store
    @State private var keyword: String
    @State private var name: String
    @State private var promptTemplate: String
    @State private var errorMessage: String?

    init(command: AICommand?) {
        self.command = command
        _keyword = State(initialValue: command?.keyword ?? "")
        _name = State(initialValue: command?.name ?? "")
        _promptTemplate = State(initialValue: command?.promptTemplate ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(command == nil ? "Add AI Command" : "Edit AI Command")
                .font(.title2.weight(.bold))

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
                            || promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
    }

    private func save() {
        // Editing keeps the UUID, so an unrelated identity change is never possible from this sheet.
        let draft = AICommand(
            id: command?.id ?? UUID(), keyword: keyword, name: name, promptTemplate: promptTemplate)
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
