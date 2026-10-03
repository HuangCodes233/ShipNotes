import Foundation
import Security

protocol AIKeychainStoring: Sendable {
    func save(_ apiKey: String, for provider: AIProvider, role: AIProfileRole) throws
    func load(for provider: AIProvider, role: AIProfileRole) throws -> String?
    func loadWithoutPrompt(for provider: AIProvider, role: AIProfileRole) throws -> String?
    func delete(for provider: AIProvider, role: AIProfileRole) throws
}

extension AIKeychainStoring {
    func save(_ apiKey: String, for provider: AIProvider) throws {
        try save(apiKey, for: provider, role: .text)
    }

    func load(for provider: AIProvider) throws -> String? {
        try load(for: provider, role: .text)
    }

    func loadWithoutPrompt(for provider: AIProvider) throws -> String? {
        try loadWithoutPrompt(for: provider, role: .text)
    }

    func delete(for provider: AIProvider) throws {
        try delete(for: provider, role: .text)
    }
}

struct AIKeychainStore: AIKeychainStoring {
    private static let service = "org.shipnotes.app.ai"

    func save(_ apiKey: String, for provider: AIProvider, role: AIProfileRole) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw AIServiceError.invalidResponse("API key is not valid UTF-8")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: provider.keychainAccount(for: role),
        ]

        // Replace if present
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AIServiceError.invalidResponse("Keychain save failed (status \(status))")
        }
    }

    func load(for provider: AIProvider, role: AIProfileRole) throws -> String? {
        try load(for: provider, role: role, allowsAuthenticationUI: true)
    }

    func loadWithoutPrompt(for provider: AIProvider, role: AIProfileRole) throws -> String? {
        try load(for: provider, role: role, allowsAuthenticationUI: false)
    }

    private func load(for provider: AIProvider, role: AIProfileRole, allowsAuthenticationUI: Bool) throws -> String? {
        var query = Self.baseQuery(
            service: Self.service,
            account: provider.keychainAccount(for: role)
        )
        query.merge([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, new in new }
        if !allowsAuthenticationUI {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }

        return try Self.loadString(query: query)
    }

    func delete(for provider: AIProvider, role: AIProfileRole) throws {
        let query = Self.baseQuery(
            service: Self.service,
            account: provider.keychainAccount(for: role)
        )
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is fine (already deleted).
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIServiceError.invalidResponse("Keychain delete failed (status \(status))")
        }
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func loadString(query: [String: Any]) throws -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        if status == errSecInteractionNotAllowed { return nil }
        guard status == errSecSuccess else {
            throw AIServiceError.invalidResponse("Keychain load failed (status \(status))")
        }
        guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}
