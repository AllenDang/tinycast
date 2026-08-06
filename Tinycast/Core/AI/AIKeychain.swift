import Foundation
import Security

/// Thin Keychain wrapper for the AI commands feature's API key — Tinycast's first secret, so nothing
/// existing needed a home for it. Everything else persisted stores to UserDefaults/plist; a bearer
/// token for a user-supplied endpoint is not something either belongs in, hence this rather than
/// reusing `AppSettings`.
///
/// Scoped to `Bundle.main.bundleIdentifier`, like every other persisted value: Dev/beta/stable each
/// get their own Keychain item, so clearing one channel's key can never touch another's.
enum AIKeychain {
    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "com.tinycast.app") + ".ai-provider"
    }
    private static let account = "api-key"

    private static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load() -> String? {
        var attributes = query()
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let base = query()
        if SecItemCopyMatching(base as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var attributes = base
            attributes[kSecValueData as String] = data
            // Available once the user has unlocked the Mac once after boot; matches how the app is
            // actually used (a menu-bar launcher isn't reached before first unlock).
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    static func delete() {
        SecItemDelete(query() as CFDictionary)
    }
}
