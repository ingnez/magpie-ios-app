import Foundation
import Security

enum KeychainStore {
    private static let service = "ai.usemagpie.ios.webkey"
    private static let fallbackPrefix = "magpie.webkey.fallback."

    static func saveWebKey(_ key: String, forServerID id: UUID) {
        let account = id.uuidString
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = clean.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: fallbackPrefix + account)
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                UserDefaults.standard.removeObject(forKey: fallbackPrefix + account)
                return
            }
        }

        // Fallback for unsigned / simulator builds without keychain entitlement (-34018)
        UserDefaults.standard.set(clean, forKey: fallbackPrefix + account)
    }

    static func loadWebKey(forServerID id: UUID) -> String? {
        let account = id.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let str = String(data: data, encoding: .utf8),
           !str.isEmpty {
            return str
        }

        return UserDefaults.standard.string(forKey: fallbackPrefix + account)
    }

    static func deleteWebKey(forServerID id: UUID) {
        let account = id.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackPrefix + account)
    }

    static func maskedPreview(_ key: String?) -> String {
        guard let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return "未配置密钥"
        }
        if trimmed.count <= 8 {
            return String(repeating: "•", count: trimmed.count)
        }
        return "\(trimmed.prefix(4))···\(trimmed.suffix(4))"
    }
}
