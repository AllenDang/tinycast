import Foundation

@MainActor
@Observable
final class AIProviderStore {
    private static let consentKey = "aiProviderEnabled"
    private static let providersKey = "aiProviders"

    private let defaults: UserDefaults

    private(set) var isEnabled: Bool
    private(set) var providers: [AIProvider]
    private var providerIDsWithAPIKey: Set<UUID>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.consentKey)
        let loadedProviders: [AIProvider]?
        if let data = defaults.data(forKey: Self.providersKey) {
            loadedProviders = try? JSONDecoder().decode([AIProvider].self, from: data)
        } else {
            loadedProviders = nil
        }
        let resolvedProviders = loadedProviders ?? []
        providers = resolvedProviders
        providerIDsWithAPIKey = Set(
            resolvedProviders.lazy.filter { AIKeychain.load(for: $0.id)?.isEmpty == false }.map(\.id))
        if loadedProviders == nil { persistProviders() }
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
        providers.append(try validated(draft))
        persistProviders()
    }

    func updateProvider(_ draft: AIProvider) throws {
        guard let index = providers.firstIndex(where: { $0.id == draft.id }) else { return }
        providers[index] = try validated(draft)
        persistProviders()
    }

    private func validated(_ draft: AIProvider) throws -> AIProvider {
        let cleaned = AIProvider(
            id: draft.id, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURLString: draft.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            models: draft.models)
        guard !cleaned.name.isEmpty else { throw AIProviderValidationError.emptyName }
        guard !cleaned.baseURLString.isEmpty else { throw AIProviderValidationError.emptyBaseURL }
        guard !cleaned.models.isEmpty else { throw AIProviderValidationError.emptyModel }
        return cleaned
    }

    func removeProvider(id: UUID) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        providers.remove(at: index)
        persistProviders()
        AIKeychain.delete(for: id)
        providerIDsWithAPIKey.remove(id)
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
        if AIKeychain.load(for: providerID)?.isEmpty == false {
            providerIDsWithAPIKey.insert(providerID)
        } else {
            providerIDsWithAPIKey.remove(providerID)
        }
    }

    // MARK: - Readiness

    /// Whether a specific provider is ready to send a request.
    func isProviderConfigured(_ providerID: UUID) -> Bool {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return false }
        return provider.baseURL != nil
            && !provider.models.isEmpty
            && providerIDsWithAPIKey.contains(providerID)
    }

    func isCommandConfigured(_ command: AICommand) -> Bool {
        guard let id = command.providerID, isProviderConfigured(id),
            let provider = provider(id: id)
        else { return false }
        return provider.resolvedModel(command.model) != nil
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
}

enum AIProviderValidationError: LocalizedError {
    case emptyName
    case emptyBaseURL
    case emptyModel

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the provider."
        case .emptyBaseURL: return "Enter a base URL for the provider."
        case .emptyModel: return "Enter at least one model name for the provider."
        }
    }
}
