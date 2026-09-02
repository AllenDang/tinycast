import Foundation
import Security

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
}
