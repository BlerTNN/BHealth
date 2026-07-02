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
    private let genericStore = KeychainSecretStore()

    private init() {}

    var hasAPIKey: Bool {
        (try? readAPIKey())?.isEmpty == false
    }

    func saveAPIKey(_ value: String) throws {
        try genericStore.save(value, service: service, account: account)
    }

    func readAPIKey() throws -> String {
        try genericStore.read(service: service, account: account)
    }

    func deleteAPIKey() throws {
        try genericStore.delete(service: service, account: account)
    }
}

final class TavilyAPIKeyStore {
    static let shared = TavilyAPIKeyStore()

    private let service = "com.tydnzs.BHealth.tavily"
    private let account = "apiKey"
    private let genericStore = KeychainSecretStore()

    private init() {}

    var hasAPIKey: Bool {
        (try? readAPIKey())?.isEmpty == false
    }

    func saveAPIKey(_ value: String) throws {
        try genericStore.save(value, service: service, account: account)
    }

    func readAPIKey() throws -> String {
        try genericStore.read(service: service, account: account)
    }

    func deleteAPIKey() throws {
        try genericStore.delete(service: service, account: account)
    }
}

private struct KeychainSecretStore {
    func save(_ value: String, service: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptyValue }
        guard let data = trimmed.data(using: .utf8) else { throw KeychainError.invalidData }

        try? delete(service: service, account: account)

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

    func read(service: String, account: String) throws -> String {
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

    func delete(service: String, account: String) throws {
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

    func message(language: AppLanguage) -> String {
        switch self {
        case .emptyValue:
            return AppText.text("API key 不能为空。", "API key cannot be empty.", language: language)
        case .invalidData:
            return AppText.text("API key 数据无法编码。", "API key data could not be encoded.", language: language)
        case .notFound:
            return AppText.text("还没有保存 DeepSeek API key。", "No DeepSeek API key has been saved.", language: language)
        case .unhandled(let status):
            return AppText.text("Keychain 操作失败：\(status)", "Keychain operation failed: \(status)", language: language)
        }
    }

    var errorDescription: String? {
        message(language: .chinese)
    }
}
