import Foundation
import Security

public enum SmartEditModelKeyStoreError: Error, Equatable {
    case unavailable
    case invalidValue
}

/// 模型 API 密钥只写入当前用户 Keychain，不进入草稿、项目文件或日志。
public struct SmartEditModelKeyStore: Sendable {
    public init() {}

    public func save(_ key: String, account: String) throws {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty, !normalizedAccount.isEmpty else {
            throw SmartEditModelKeyStoreError.invalidValue
        }
        #if canImport(Security)
        let data = Data(normalizedKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.runoverlay.smart-edit",
            kSecAttrAccount as String: normalizedAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.runoverlay.smart-edit",
                kSecAttrAccount as String: normalizedAccount
            ]
            let attributes: [String: Any] = [kSecValueData as String: data]
            guard SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
                    == errSecSuccess else {
                throw SmartEditModelKeyStoreError.unavailable
            }
        } else if status != errSecSuccess {
            throw SmartEditModelKeyStoreError.unavailable
        }
        #else
        throw SmartEditModelKeyStoreError.unavailable
        #endif
    }

    public func load(account: String) throws -> String? {
        let normalizedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAccount.isEmpty else {
            throw SmartEditModelKeyStoreError.invalidValue
        }
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.runoverlay.smart-edit",
            kSecAttrAccount as String: normalizedAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw SmartEditModelKeyStoreError.unavailable
        }
        return value
        #else
        throw SmartEditModelKeyStoreError.unavailable
        #endif
    }

    public func delete(account: String) throws {
        let normalizedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAccount.isEmpty else {
            throw SmartEditModelKeyStoreError.invalidValue
        }
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.runoverlay.smart-edit",
            kSecAttrAccount as String: normalizedAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SmartEditModelKeyStoreError.unavailable
        }
        #else
        throw SmartEditModelKeyStoreError.unavailable
        #endif
    }
}
