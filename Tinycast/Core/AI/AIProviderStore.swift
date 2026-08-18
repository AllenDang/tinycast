import Foundation

/// A user-configured OpenAI-compatible endpoint. The API key lives in the Keychain (keyed by `id`),
/// not in UserDefaults — only the name, base URL and model are persisted in plain storage.
struct AIProvider: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var baseURLString: String
    var model: String

    init(id: UUID = UUID(), name: String, baseURLString: String, model: String) {
        self.id = id
        self.name = name
        self.baseURLString = baseURLString
        self.model = model
    }

    var baseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return url
    }
}

/// Consent and connection settings for the AI commands feature. Manages multiple user-configured
/// OpenAI-compatible endpoints; each AI command picks one. The global consent flag ships **off** and
/// lives here rather than on `AppSettings`, so `SettingsBackup` can never silently grant network
/// access. Every entry point that could reach the network re-checks `isEnabled` rather than trusting
/// a caller.
@MainActor
@Observable
final class AIProviderStore {
    private static let consentKey = "aiProviderEnabled"
    private static let providersKey = "aiProviders"
    // Legacy keys, read once during migration then cleared.
    private static let legacyBaseURLKey = "aiProviderBaseURL"
    private static let legacyModelKey = "aiProviderModel"

    private let defaults: UserDefaults

    private(set) var isEnabled: Bool
    private(set) var providers: [AIProvider]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.consentKey)
        if let data = defaults.data(forKey: Self.providersKey),
            let decoded = try? JSONDecoder().decode([AIProvider].self, from: data)
        {
            providers = decoded
        } else {
            providers = Self.migrateFromLegacy(defaults: defaults)
            persistProviders()
        }
    }

    // MARK: - Consent

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)
    }

    // MARK: - Provider CRUD

    func provider(id: UUID) -> AIProvider? {
        providers.first { $0.id == id }
    }

    func addProvider(_ draft: AIProvider) throws {
        let cleaned = AIProvider(
            id: draft.id, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURLString: draft.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            model: draft.model.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cleaned.name.isEmpty else { throw AIProviderValidationError.emptyName }
        guard !cleaned.baseURLString.isEmpty else { throw AIProviderValidationError.emptyBaseURL }
        guard !cleaned.model.isEmpty else { throw AIProviderValidationError.emptyModel }
        providers.append(cleaned)
        persistProviders()
    }

    func updateProvider(_ draft: AIProvider) throws {
        guard let index = providers.firstIndex(where: { $0.id == draft.id }) else { return }
        let cleaned = AIProvider(
            id: draft.id, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURLString: draft.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            model: draft.model.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cleaned.name.isEmpty else { throw AIProviderValidationError.emptyName }
        guard !cleaned.baseURLString.isEmpty else { throw AIProviderValidationError.emptyBaseURL }
        guard !cleaned.model.isEmpty else { throw AIProviderValidationError.emptyModel }
        providers[index] = cleaned
        persistProviders()
    }

    func removeProvider(id: UUID) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        providers.remove(at: index)
        persistProviders()
        AIKeychain.delete(for: id)
    }

    // MARK: - API key (Keychain-backed)

    func apiKey(for providerID: UUID) -> String {
        AIKeychain.load(for: providerID) ?? ""
    }

    func setAPIKey(_ value: String, for providerID: UUID) {
        if value.isEmpty {
            AIKeychain.delete(for: providerID)
        } else {
            AIKeychain.save(value, for: providerID)
        }
    }

    // MARK: - Readiness

    /// Whether a specific provider is ready to send a request.
    func isProviderConfigured(_ providerID: UUID) -> Bool {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return false }
        return provider.baseURL != nil
            && !provider.model.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey(for: providerID).isEmpty
    }

    /// At least one provider is configured and consent is on — the feature can match keywords.
    var isConfigured: Bool {
        isEnabled && providers.contains(where: { isProviderConfigured($0.id) })
    }

    // MARK: - Persistence

    private func persistProviders() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: Self.providersKey)
    }

    // MARK: - Migration

    private static func migrateFromLegacy(defaults: UserDefaults) -> [AIProvider] {
        let oldBaseURL = defaults.string(forKey: legacyBaseURLKey) ?? ""
        let oldModel = defaults.string(forKey: legacyModelKey) ?? ""
        guard !oldBaseURL.isEmpty || !oldModel.isEmpty else { return [] }
        let provider = AIProvider(name: "Default", baseURLString: oldBaseURL, model: oldModel)
        if let oldKey = AIKeychain.loadLegacy(), !oldKey.isEmpty {
            AIKeychain.save(oldKey, for: provider.id)
            AIKeychain.deleteLegacy()
        }
        defaults.removeObject(forKey: legacyBaseURLKey)
        defaults.removeObject(forKey: legacyModelKey)
        return [provider]
    }
}

enum AIProviderValidationError: LocalizedError {
    case emptyName
    case emptyBaseURL
    case emptyModel

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the provider."
        case .emptyBaseURL: return "Enter a base URL for the provider."
        case .emptyModel: return "Enter a model name for the provider."
        }
    }
}
