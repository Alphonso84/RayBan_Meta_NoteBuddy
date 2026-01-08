//
//  OpenAIAPIKeyManager.swift
//  Smart Glasses
//
//  Securely stores OpenAI API key in iOS Keychain
//

import Foundation
import Security

class OpenAIAPIKeyManager {

    // MARK: - Singleton

    static let shared = OpenAIAPIKeyManager()

    // MARK: - Properties

    private let service = "com.smartglasses.openai"
    private let account = "api_key"

    private init() {}

    // MARK: - Public API

    /// Get or set the OpenAI API key
    var apiKey: String? {
        get { loadFromKeychain() }
        set {
            if let key = newValue, !key.isEmpty {
                saveToKeychain(key)
            } else {
                deleteFromKeychain()
            }
        }
    }

    /// Check if an API key is configured
    var hasAPIKey: Bool {
        apiKey != nil && !(apiKey?.isEmpty ?? true)
    }

    /// Clear the stored API key
    func clearAPIKey() {
        deleteFromKeychain()
    }

    // MARK: - Keychain Operations

    private func saveToKeychain(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }

        // Delete existing item first
        deleteFromKeychain()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            print("[OpenAIAPIKey] Failed to save API key: \(status)")
        } else {
            print("[OpenAIAPIKey] API key saved to Keychain")
        }
    }

    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            print("[OpenAIAPIKey] Failed to delete API key: \(status)")
        }
    }
}

// MARK: - API Key Validation

extension OpenAIAPIKeyManager {

    /// Basic validation of API key format
    /// Note: This doesn't verify the key is valid with OpenAI, just that it looks reasonable
    func isValidFormat(_ key: String) -> Bool {
        // OpenAI API keys typically start with "sk-" and are 51+ characters
        // Project keys start with "sk-proj-"
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedKey.count >= 40 && trimmedKey.hasPrefix("sk-")
    }

    /// Validate and save an API key
    /// - Parameter key: The API key to validate and save
    /// - Returns: True if the key was saved, false if validation failed
    @discardableResult
    func setAPIKey(_ key: String) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidFormat(trimmedKey) else {
            print("[OpenAIAPIKey] Invalid API key format")
            return false
        }

        apiKey = trimmedKey
        return true
    }
}
