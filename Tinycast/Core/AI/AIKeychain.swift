import Foundation
import Security

/// Thin Keychain wrapper for the AI commands feature's API keys — one entry per provider, keyed by
/// provider ID. Scoped to `Bundle.main.bundleIdentifier`, like every other persisted value:
/// Dev/beta/stable each get their own Keychain items, so clearing one channel's keys can never touch
/// another's.
enum AIKeychain {
    private static func service(for providerID: UUID) -> String {
        (Bundle.main.bundleIdentifier ?? "com.tinycast.app") + ".ai-provider.\(providerID.uuidString)"
    }
    private static let account = "api-key"

    private static func query(for providerID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: providerID),
            kSecAttrAccount as String: account
        ]
    }

    static func load(for providerID: UUID) -> String? {
        var attributes = query(for: providerID)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, for providerID: UUID) {
        guard let data = value.data(using: .utf8) else { return }
        let base = query(for: providerID)
        if SecItemCopyMatching(base as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var attributes = base
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    static func delete(for providerID: UUID) {
        SecItemDelete(query(for: providerID) as CFDictionary)
    }

    // MARK: - Legacy (single-provider migration)

    private static var legacyService: String {
        (Bundle.main.bundleIdentifier ?? "com.tinycast.app") + ".ai-provider"
    }

    private static func legacyQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: account
        ]
    }

    /// The old single-provider key, read once during migration and then deleted.
    static func loadLegacy() -> String? {
        var attributes = legacyQuery()
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteLegacy() {
        SecItemDelete(legacyQuery() as CFDictionary)
    }
}
