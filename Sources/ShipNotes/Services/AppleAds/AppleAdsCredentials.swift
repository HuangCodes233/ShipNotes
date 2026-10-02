import Foundation
import Security

struct AppleAdsCredentials: Codable, Equatable, Sendable {
    var name: String
    var clientId: String
    var teamId: String
    var keyId: String
    var privateKeyPEM: String
    var adAccountId: String?

    var trimmed: AppleAdsCredentials {
        AppleAdsCredentials(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines),
            teamId: teamId.trimmingCharacters(in: .whitespacesAndNewlines),
            keyId: keyId.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines),
            adAccountId: adAccountId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    var accountName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Apple Ads" : trimmedName
    }
}

struct AppleAdsCredentialSummary: Equatable, Sendable {
    var name: String
    var clientId: String
    var teamId: String
    var keyId: String
    var adAccountId: String?
}

protocol AppleAdsCredentialStoring: Sendable {
    func load() throws -> AppleAdsCredentials?
    func save(_ credentials: AppleAdsCredentials) throws
    func delete() throws
}

enum AppleAdsCredentialError: LocalizedError, Equatable, Sendable {
    case missingClientId
    case missingTeamId
    case missingKeyId
    case missingPrivateKey
    case keychainSaveFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    case invalidStoredData

    var errorDescription: String? {
        switch self {
        case .missingClientId:
            L("Apple Ads Client ID is required.")
        case .missingTeamId:
            L("Apple Ads Team ID is required.")
        case .missingKeyId:
            L("Apple Ads Key ID is required.")
        case .missingPrivateKey:
            L("Apple Ads private key is required. Generate an EC P-256 key and upload the public key in Apple Ads.")
        case .keychainSaveFailed(let status):
            "Could not save Apple Ads credentials to Keychain (status \(status))."
        case .keychainReadFailed(let status):
            "Could not read Apple Ads credentials from Keychain (status \(status))."
        case .keychainDeleteFailed(let status):
            "Could not remove Apple Ads credentials from Keychain (status \(status))."
        case .invalidStoredData:
            L("Stored Apple Ads credentials are invalid. Re-enter the API key.")
        }
    }
}

extension AppleAdsCredentials {
    func validated() throws -> AppleAdsCredentials {
        let value = trimmed
        guard !value.clientId.isEmpty else { throw AppleAdsCredentialError.missingClientId }
        guard !value.teamId.isEmpty else { throw AppleAdsCredentialError.missingTeamId }
        guard !value.keyId.isEmpty else { throw AppleAdsCredentialError.missingKeyId }
        guard !value.privateKeyPEM.isEmpty else { throw AppleAdsCredentialError.missingPrivateKey }
        return value
    }

    var summary: AppleAdsCredentialSummary {
        AppleAdsCredentialSummary(
            name: accountName,
            clientId: clientId,
            teamId: teamId,
            keyId: keyId,
            adAccountId: adAccountId
        )
    }
}

struct AppleAdsKeychainStore: AppleAdsCredentialStoring, Sendable {
    static let serviceIdentifier = "org.shipnotes.app.appleads"
    private let service = AppleAdsKeychainStore.serviceIdentifier
    private let account = "default"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() throws -> AppleAdsCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AppleAdsCredentialError.keychainReadFailed(status)
        }
        guard let data = item as? Data,
              let credentials = try? decoder.decode(AppleAdsCredentials.self, from: data) else {
            throw AppleAdsCredentialError.invalidStoredData
        }
        return credentials
    }

    func save(_ credentials: AppleAdsCredentials) throws {
        let data = try encoder.encode(credentials.validated())
        var query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AppleAdsCredentialError.keychainSaveFailed(updateStatus)
        }

        query.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppleAdsCredentialError.keychainSaveFailed(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppleAdsCredentialError.keychainDeleteFailed(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
