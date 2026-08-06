import Foundation

/// Consent and connection settings for the AI commands feature: a user-supplied OpenAI-compatible
/// endpoint, model and API key. No provider name or URL is ever baked in — this is entirely the
/// user's own configuration — which is also why, unlike `CurrencyRateStore`, there is no bundled
/// `provider` constant to show in Settings.
///
/// Mirrors `CurrencyRateStore`'s consent shape (the app's reference implementation for a networked
/// feature): ships **off**, the flag lives here rather than on `AppSettings` so `SettingsBackup`
/// can never silently grant network access, and every entry point that could reach the network
/// re-checks `isEnabled` rather than trusting a caller. Unlike currency conversion this feature has
/// no periodic fetch — each request is a single, user-initiated round trip — so there is no refresh
/// loop to start/stop, only the consent flag itself.
@MainActor
@Observable
final class AIProviderStore {
    private static let consentKey = "aiProviderEnabled"
    private static let baseURLKey = "aiProviderBaseURL"
    private static let modelKey = "aiProviderModel"

    private let defaults: UserDefaults

    /// Explicit user consent. Deliberately *not* part of `AppSettings`: `SettingsBackup` mirrors that
    /// type field-for-field, and an imported config must never be able to silently grant network access.
    private(set) var isEnabled: Bool

    /// Not sensitive, so — unlike the API key — these live in plain UserDefaults alongside the consent flag.
    var baseURLString: String {
        didSet {
            guard baseURLString != oldValue else { return }
            defaults.set(baseURLString, forKey: Self.baseURLKey)
        }
    }
    var model: String {
        didSet {
            guard model != oldValue else { return }
            defaults.set(model, forKey: Self.modelKey)
        }
    }

    /// The Keychain-backed secret. No in-memory cache: read and write go straight through, so this
    /// store never holds the plaintext key longer than a single access needs it.
    var apiKey: String {
        get { AIKeychain.load() ?? "" }
        set {
            if newValue.isEmpty {
                AIKeychain.delete()
            } else {
                AIKeychain.save(newValue)
            }
        }
    }

    var baseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return url
    }

    /// Ready to send a request: consent, a parseable endpoint, a model name and a stored key.
    var isConfigured: Bool {
        isEnabled && baseURL != nil && !model.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.isEmpty
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Absent reads as false, the only safe default for a network feature.
        isEnabled = defaults.bool(forKey: Self.consentKey)
        baseURLString = defaults.string(forKey: Self.baseURLKey) ?? ""
        model = defaults.string(forKey: Self.modelKey) ?? ""
    }

    /// The Settings toggle's only entry point for turning the feature *on* — called after the user
    /// accepts the consent dialog. Turning it off never needs a dialog, so the pane can call this
    /// directly either way. The endpoint, model and key are the user's own configuration, not
    /// downloaded data, so — unlike `CurrencyRateStore.setEnabled(false)` — disabling leaves them in
    /// place for a quick re-enable; only the "recognizes keywords / makes requests" behavior stops.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)
    }
}
