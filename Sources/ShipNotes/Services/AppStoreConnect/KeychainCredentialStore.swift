import Foundation
import Security

struct KeychainCredentialStore: AppStoreConnectCredentialStoring, Sendable {
    private let service = "org.shipnotes.app.appstoreconnect"
    private let account = "default"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() throws -> AppStoreConnectCredentials? {
        try load(service: service)
    }

    func save(_ credentials: AppStoreConnectCredentials) throws {
        let data = try encoder.encode(credentials.validated())
        var query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AppStoreConnectCredentialError.keychainSaveFailed(updateStatus)
        }

        query.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppStoreConnectCredentialError.keychainSaveFailed(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppStoreConnectCredentialError.keychainDeleteFailed(status)
        }
    }

    private var baseQuery: [String: Any] {
        baseQuery(service: service)
    }

    private func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func load(service: String) throws -> AppStoreConnectCredentials? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AppStoreConnectCredentialError.keychainReadFailed(status)
        }
        guard let data = item as? Data,
            let credentials = try? decoder.decode(AppStoreConnectCredentials.self, from: data)
        else {
            throw AppStoreConnectCredentialError.invalidStoredData
        }
        return credentials
    }
}
