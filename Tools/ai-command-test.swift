import Foundation

/// Pure-Foundation coverage for `AICommand`: the store's CRUD/validation (mirroring
/// `Tools/custom-command-test.swift`) and `AICommand.firstMatch`, the raw-query-string recognizer the
/// launcher card and `AppCore.beginAICommand` both depend on. Nothing here touches the network or the
/// Keychain — those live in `AIProviderStore`/`AIChatClient`/`AICommandSession`, which aren't pure and
/// aren't covered by this harness.
@main
struct AICommandTests {
    @MainActor
    static func main() async {
        let suiteName = "com.tinycast.ai-command-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("FAIL  could not create an isolated UserDefaults suite")
            exit(1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // MARK: Store

        let store = AICommandStore(defaults: defaults)
        let added = try? store.add(
            AICommand(keyword: "  trans  ", name: "  Translate  ", promptTemplate: "Translate: {input}"))
        check("add trims the keyword", added?.keyword == "trans")
        check("add trims the name", added?.name == "Translate")
        check("add keeps the prompt", added?.promptTemplate == "Translate: {input}")

        guard let added else {
            print("FAIL  add returned nothing; the remaining cases need it")
            exit(1)
        }

        var duplicateRejected = false
        do {
            _ = try store.add(AICommand(keyword: "TRANS", name: "Other", promptTemplate: "{input}"))
        } catch AICommandValidationError.duplicateKeyword {
            duplicateRejected = true
        } catch {}
        check("a keyword differing only in case is rejected", duplicateRejected)

        var whitespaceRejected = false
        do {
            _ = try store.add(AICommand(keyword: "fix it", name: "Fix", promptTemplate: "{input}"))
        } catch AICommandValidationError.keywordContainsWhitespace {
            whitespaceRejected = true
        } catch {}
        check("a keyword containing whitespace is rejected", whitespaceRejected)

        var emptyPromptRejected = false
        do {
            _ = try store.add(AICommand(keyword: "empty", name: "Empty", promptTemplate: "   "))
        } catch AICommandValidationError.emptyPrompt {
            emptyPromptRejected = true
        } catch {}
        check("an all-whitespace prompt is rejected", emptyPromptRejected)

        try? store.update(
            AICommand(id: added.id, keyword: "tr", name: "Translate It", promptTemplate: "{input}"))
        check("update keeps the id", store.command(id: added.id) != nil)
        check("update applies the new keyword", store.command(id: added.id)?.keyword == "tr")
        check("update applies the new name", store.command(id: added.id)?.name == "Translate It")

        let expected = store.commands
        check(
            "commands survive a reload",
            AICommandStore(defaults: defaults).commands == expected)

        store.replace(with: [
            AICommand(keyword: "fix", name: "Fix Grammar", promptTemplate: "Fix: {input}"),
            // A duplicate keyword in the same import batch must not survive sanitization either.
            AICommand(keyword: "FIX", name: "Duplicate", promptTemplate: "{input}")
        ])
        check("import keeps exactly one of a duplicate pair", store.commands.count == 1)
        check("import keeps the first of a duplicate pair", store.commands.first?.name == "Fix Grammar")

        _ = store.remove(id: store.commands[0].id)
        check("remove leaves an empty store", store.commands.isEmpty)

        // MARK: firstMatch

        let commands = [
            AICommand(keyword: "trans", name: "Translate", promptTemplate: "Translate: {input}"),
            AICommand(keyword: "fix", name: "Fix Grammar", promptTemplate: "Fix: {input}")
        ]

        let matched = AICommand.firstMatch(in: commands, query: "trans hello there")
        check("a keyword followed by text matches", matched?.command.name == "Translate")
        check("the match carries the text after the keyword", matched?.input == "hello there")

        check(
            "a bare keyword with no trailing space matches nothing yet",
            AICommand.firstMatch(in: commands, query: "trans") == nil)
        check(
            "a keyword followed only by whitespace matches nothing",
            AICommand.firstMatch(in: commands, query: "trans   ") == nil)
        check(
            "an unregistered keyword matches nothing",
            AICommand.firstMatch(in: commands, query: "nope hello") == nil)
        check(
            "matching is case-insensitive",
            AICommand.firstMatch(in: commands, query: "TRANS hello")?.command.name == "Translate")
        check(
            "extra internal whitespace is trimmed from the input",
            AICommand.firstMatch(in: commands, query: "fix   messy sentence  ")?.input
                == "messy sentence")
        check(
            "an app search with no space at all matches nothing",
            AICommand.firstMatch(in: commands, query: "safari") == nil)
        check(
            "an empty query matches nothing",
            AICommand.firstMatch(in: commands, query: "") == nil)

        // MARK: pendingKeyword

        check(
            "a bare exact keyword is a pending hint",
            AICommand.pendingKeyword(in: commands, query: "trans")?.name == "Translate")
        check(
            "a keyword plus a trailing space with nothing after it is still pending",
            AICommand.pendingKeyword(in: commands, query: "trans ")?.name == "Translate")
        check(
            "a keyword plus only whitespace after it is still pending",
            AICommand.pendingKeyword(in: commands, query: "trans   ")?.name == "Translate")
        check(
            "pending matching is case-insensitive",
            AICommand.pendingKeyword(in: commands, query: "TRANS")?.name == "Translate")
        check(
            "a keyword prefix that isn't the whole keyword is not pending",
            AICommand.pendingKeyword(in: commands, query: "tra") == nil)
        check(
            "an unregistered word is not pending",
            AICommand.pendingKeyword(in: commands, query: "nope") == nil)
        check(
            "an empty query is not pending",
            AICommand.pendingKeyword(in: commands, query: "") == nil)
        check(
            "a ready match is never also reported as pending",
            AICommand.pendingKeyword(in: commands, query: "trans hello") == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
