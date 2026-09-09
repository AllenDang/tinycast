import Foundation

struct AIProvider: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var baseURLString: String
    var models: [String]

    init(id: UUID = UUID(), name: String, baseURLString: String, models: [String]) {
        self.id = id
        self.name = name
        self.baseURLString = baseURLString
        self.models = Self.normalizedModels(models)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURLString, models, model
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        baseURLString = try values.decode(String.self, forKey: .baseURLString)
        let names = try values.decodeIfPresent([String].self, forKey: .models)
            ?? [values.decode(String.self, forKey: .model)]
        models = Self.normalizedModels(names)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(baseURLString, forKey: .baseURLString)
        try values.encode(models, forKey: .models)
    }

    static func normalizedModels(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.compactMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seen.insert(trimmed).inserted ? trimmed : nil
        }
    }

    func resolvedModel(_ selection: String?) -> String? {
        // Commands without a selection retain the provider's default (first) model.
        guard let selection else { return models.first }
        return models.contains(selection) ? selection : nil
    }

    var baseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return url
    }
}
