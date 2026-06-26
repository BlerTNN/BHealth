//
//  KeychainAPIKeyStore.swift
//  BHealth
//
//  Created by Codex on 2026-06-26.
//

import Foundation
import Security

final class KeychainAPIKeyStore {
    static let shared = KeychainAPIKeyStore()

    private let service = "com.tydnzs.BHealth.deepseek"
    private let account = "apiKey"

    private init() {}

    var hasAPIKey: Bool {
        (try? readAPIKey())?.isEmpty == false
    }

    func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptyValue }
        guard let data = trimmed.data(using: .utf8) else { throw KeychainError.invalidData }

        try? deleteAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func readAPIKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return value
    }

    func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case emptyValue
    case invalidData
    case notFound
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyValue:
            return "API key 不能为空。"
        case .invalidData:
            return "API key 数据无法编码。"
        case .notFound:
            return "还没有保存 DeepSeek API key。"
        case .unhandled(let status):
            return "Keychain 操作失败：\(status)"
        }
    }
}
