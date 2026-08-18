import Foundation

/// A user-authored `<keyword> <text>` command: typing the keyword followed by a space and some text
/// in the launcher recognizes it, exactly the way `CalcEngine` recognizes `"5+3"` — at the raw query
/// string, not by fuzzy-matching a row. What actually happens to the text (translate it, fix its
/// grammar, anything else) is entirely the user's `promptTemplate`; Tinycast bakes in no commands and
/// no provider.
struct AICommand: Codable, Hashable, Identifiable, Sendable {
    /// One glyph for every AI command — launcher card, Settings row and its consent dialog, so they read as the same feature.
    static let sfSymbol = "sparkles"

    let id: UUID
    var keyword: String
    var name: String
    /// Expanded through `SnippetTemplateEngine`, the app's one template parser; `{input}` is the text
    /// typed after the keyword. Any other token the engine understands (`{date}`, `{clipboard}`, …)
    /// works too, since this runs through the same expansion as a snippet or quicklink.
    var promptTemplate: String
    /// The provider that handles this command's requests. Optional for migration — old stored commands
    /// decoded before the field existed read as nil, and the store's sanitizer drops them.
    var providerID: UUID?

    init(id: UUID = UUID(), keyword: String, name: String, promptTemplate: String,
         providerID: UUID? = nil)
    {
        self.id = id
        self.keyword = keyword
        self.name = name
        self.promptTemplate = promptTemplate
        self.providerID = providerID
    }
}

/// What the raw query resolved to: the command whose keyword led the query, and the text after it.
struct AICommandMatch: Equatable, Sendable {
    let command: AICommand
    let input: String
}

extension AICommand {
    /// Recognizes `<keyword> <text>` in the raw query string — the same layer `CalcEngine.evaluate`
    /// parses at, not a search over already-matched rows. The keyword must be followed by whitespace
    /// and at least one more non-whitespace character; a bare keyword still being typed (`"trans"`,
    /// no trailing space yet) matches nothing, because there is no text to act on yet and showing a
    /// card too early would fire on every keyword-shaped word a user happens to type.
    static func firstMatch(in commands: [AICommand], query: String) -> AICommandMatch? {
        guard let spaceIndex = query.firstIndex(where: \.isWhitespace) else { return nil }
        let keyword = query[..<spaceIndex]
        guard !keyword.isEmpty else { return nil }
        let input = query[query.index(after: spaceIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        guard
            let command = commands.first(where: {
                $0.keyword.compare(keyword, options: .caseInsensitive) == .orderedSame
            })
        else { return nil }
        return AICommandMatch(command: command, input: input)
    }

    /// The command whose keyword the query currently spells with no argument text yet — either still
    /// typing the keyword itself (`"trans"`) or having just typed the trailing space (`"trans "`).
    /// `firstMatch` deliberately matches nothing at this point since there's nothing to run, which
    /// otherwise leaves the launcher showing no feedback at all that the keyword was even recognized
    /// — an AI command is never an `AppEntry` (see docs/ai-commands.md), so it never gets a fuzzy-matched
    /// row the way a custom command or quicklink would. This fills that gap without running anything:
    /// callers only ever use it to show a hint, never to fire a request.
    static func pendingKeyword(in commands: [AICommand], query: String) -> AICommand? {
        guard firstMatch(in: commands, query: query) == nil else { return nil }
        let keyword = query.firstIndex(where: \.isWhitespace).map { query[..<$0] } ?? Substring(query)
        guard !keyword.isEmpty else { return nil }
        return commands.first { $0.keyword.compare(keyword, options: .caseInsensitive) == .orderedSame }
    }
}

enum AICommandValidationError: LocalizedError {
    case emptyKeyword
    case emptyName
    case emptyPrompt
    case keywordContainsWhitespace
    case duplicateKeyword
    case invalidCharacter
    case missingProvider

    var errorDescription: String? {
        switch self {
        case .emptyKeyword: return "Enter a keyword to trigger this command."
        case .emptyName: return "Enter a name for the command."
        case .emptyPrompt: return "Enter a prompt for the command."
        case .keywordContainsWhitespace: return "A keyword can't contain spaces."
        case .duplicateKeyword: return "An AI command with this keyword already exists."
        case .invalidCharacter: return "Keywords, names and prompts cannot contain null characters."
        case .missingProvider: return "Select a provider for the command."
        }
    }
}

@MainActor
@Observable
final class AICommandStore {
    private static let defaultsKey = "aiCommands"

    private let defaults: UserDefaults
    private(set) var commands: [AICommand]
    @ObservationIgnored var onChange: (([AICommand]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([AICommand].self, from: $0) } ?? []
        commands = Self.sanitized(decoded)
        if commands != decoded { persist() }
    }

    // periphery:ignore - only called by Tools/ai-command-test.swift, which Periphery doesn't index.
    func command(id: UUID) -> AICommand? {
        commands.first { $0.id == id }
    }

    // Takes a whole draft rather than a parameter per field so adding an option doesn't churn every call site.
    @discardableResult
    func add(_ draft: AICommand) throws -> AICommand {
        let value = try validated(draft)
        commit(commands + [value])
        return value
    }

    func update(_ draft: AICommand) throws {
        guard let index = commands.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = commands
        updated[index] = value
        commit(updated)
    }

    @discardableResult
    func remove(id: UUID) -> AICommand? {
        guard let index = commands.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = commands
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    // Mirrors `CustomCommandStore.replace(with:)`'s shape for a future native-backup import; not wired to backups yet, so only Tools/ai-command-test.swift (which Periphery doesn't index) calls it.
    // periphery:ignore
    @discardableResult
    func replace(with newCommands: [AICommand]) -> Int {
        let updated = Self.sanitized(newCommands)
        commit(updated)
        return updated.count
    }

    private func validated(_ draft: AICommand) throws -> AICommand {
        var value = draft
        value.keyword = draft.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.promptTemplate = draft.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.keyword.isEmpty else { throw AICommandValidationError.emptyKeyword }
        guard !value.name.isEmpty else { throw AICommandValidationError.emptyName }
        guard !value.promptTemplate.isEmpty else { throw AICommandValidationError.emptyPrompt }
        guard !value.keyword.contains(where: \.isWhitespace) else {
            throw AICommandValidationError.keywordContainsWhitespace
        }
        guard !value.keyword.contains("\0"), !value.name.contains("\0"),
            !value.promptTemplate.contains("\0")
        else { throw AICommandValidationError.invalidCharacter }
        guard value.providerID != nil else { throw AICommandValidationError.missingProvider }
        guard
            !commands.contains(where: {
                $0.id != value.id
                    && $0.keyword.compare(value.keyword, options: .caseInsensitive) == .orderedSame
            })
        else { throw AICommandValidationError.duplicateKeyword }
        return value
    }

    private func commit(_ updated: [AICommand]) {
        guard updated != commands else { return }
        commands = updated
        persist()
        onChange?(updated)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func sanitized(_ values: [AICommand]) -> [AICommand] {
        var ids = Set<UUID>()
        var keywords = Set<String>()
        var result: [AICommand] = []
        for value in values {
            var cleaned = value
            cleaned.keyword = value.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.promptTemplate = value.promptTemplate.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let foldedKeyword = cleaned.keyword.folding(options: [.caseInsensitive], locale: .current)
            guard !cleaned.keyword.isEmpty, !cleaned.name.isEmpty, !cleaned.promptTemplate.isEmpty,
                !cleaned.keyword.contains(where: \.isWhitespace),
                !cleaned.keyword.contains("\0"), !cleaned.name.contains("\0"),
                !cleaned.promptTemplate.contains("\0"), ids.insert(cleaned.id).inserted,
                keywords.insert(foldedKeyword).inserted,
                cleaned.providerID != nil
            else { continue }
            result.append(cleaned)
        }
        return result
    }
}
