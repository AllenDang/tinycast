import Foundation

@main
struct AIProviderTests {
    @MainActor
    static func main() throws {
        var failures = 0
        func check(_ label: String, _ condition: Bool) {
            print("\(condition ? "PASS" : "FAIL")  \(label)")
            if !condition { failures += 1 }
        }

        let id = UUID()
        let legacy = Data("""
            {"id":"\(id)","name":"Example","baseURLString":"https://example.com/v1","model":" old "}
            """.utf8)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let migrated = try decoder.decode(AIProvider.self, from: legacy)
        check("legacy provider preserves identity and Keychain association", migrated.id == id)
        check("legacy model becomes a single trimmed model", migrated.models == ["old"])
        let encoded = try encoder.encode(migrated)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        check("writes only the new models field", object?["model"] == nil && object?["models"] != nil)
        check("migrated provider round trips", try decoder.decode(AIProvider.self, from: encoded) == migrated)

        var provider = AIProvider(
            id: id, name: "Example", baseURLString: "https://example.com/v1",
            models: [" first ", "", "second", "first", "\n", "SECOND"])
        check("normalization preserves order and case, removes blanks and duplicates",
              provider.models == ["first", "second", "SECOND"])
        check("multiple models round trip",
              try decoder.decode(AIProvider.self, from: encoder.encode(provider)) == provider)
        check("legacy command uses the first model", provider.resolvedModel(nil) == "first")
        check("explicit selection uses the requested model", provider.resolvedModel("second") == "second")
        check("missing selection never silently falls back", provider.resolvedModel("missing") == nil)
        provider.models.removeAll { $0 == "second" }
        check("removed model disables its command", provider.resolvedModel("second") == nil)
        provider.models = []
        check("empty model list has no default", provider.resolvedModel(nil) == nil)

        let both = Data("""
            {"id":"\(id)","name":"Example","baseURLString":"https://example.com",
             "models":[" new ","new"],"model":"old"}
            """.utf8)
        check("new list takes precedence and is normalized on decode",
              try decoder.decode(AIProvider.self, from: both).models == ["new"])

        let legacyCommand = Data("""
            {"id":"\(UUID())","keyword":"ask","name":"Ask","promptTemplate":"{input}",
             "providerID":"\(id)"}
            """.utf8)
        let command = try decoder.decode(AICommand.self, from: legacyCommand)
        check("old command decodes without a model", command.model == nil)
        check("old command still resolves its old provider model",
              migrated.resolvedModel(command.model) == "old")

        let suiteName = "com.tinycast.ai-provider-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AICommandStore(defaults: defaults)
        var selected = command
        selected.model = "second"
        try store.add(selected)
        check("command selection survives persistence",
              AICommandStore(defaults: defaults).commands.first?.model == "second")
        selected.model = "first"
        try store.update(selected)
        check("command model can change", store.commands.first?.model == "first")
        store.replace(with: [selected])
        check("sanitization retains model selection", store.commands.first?.model == "first")

        if failures > 0 { exit(1) }
    }
}
