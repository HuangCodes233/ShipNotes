import Foundation

struct AppStoreConnectCredentials: Codable, Equatable, Sendable {
    var name: String
    var issuerId: String
    var keyId: String
    var privateKeyPEM: String

    var trimmed: AppStoreConnectCredentials {
        AppStoreConnectCredentials(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            issuerId: issuerId.trimmingCharacters(in: .whitespacesAndNewlines),
            keyId: keyId.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var accountName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "App Store Connect" : trimmedName
    }
}

struct AppStoreConnectCredentialSummary: Equatable, Sendable {
    var name: String
    var issuerId: String
    var keyId: String
}

protocol AppStoreConnectCredentialStoring: Sendable {
    func load() throws -> AppStoreConnectCredentials?
    func save(_ credentials: AppStoreConnectCredentials) throws
    func delete() throws
}

enum AppStoreConnectCredentialError: LocalizedError, Equatable, Sendable {
    case missingIssuerId
    case missingKeyId
    case missingPrivateKey
    case keychainSaveFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    case invalidStoredData

    var errorDescription: String? {
        switch self {
        case .missingIssuerId:
            "Issuer ID is required."
        case .missingKeyId:
            "Key ID is required."
        case .missingPrivateKey:
            "Private key is required. Import or paste the .p8 key from App Store Connect."
        case .keychainSaveFailed(let status):
            "Could not save App Store Connect credentials to Keychain (status \(status))."
        case .keychainReadFailed(let status):
            "Could not read App Store Connect credentials from Keychain (status \(status))."
        case .keychainDeleteFailed(let status):
            "Could not remove App Store Connect credentials from Keychain (status \(status))."
        case .invalidStoredData:
            "Stored App Store Connect credentials are invalid. Re-enter the API key."
        }
    }
}

extension AppStoreConnectCredentials {
    func validated() throws -> AppStoreConnectCredentials {
        let value = trimmed
        guard !value.issuerId.isEmpty else { throw AppStoreConnectCredentialError.missingIssuerId }
        guard !value.keyId.isEmpty else { throw AppStoreConnectCredentialError.missingKeyId }
        guard !value.privateKeyPEM.isEmpty else { throw AppStoreConnectCredentialError.missingPrivateKey }
        return value
    }

    var summary: AppStoreConnectCredentialSummary {
        AppStoreConnectCredentialSummary(name: accountName, issuerId: issuerId, keyId: keyId)
    }
}

enum CredentialLoadResult: Sendable {
    case success(AppStoreConnectCredentials?)
    case failure(AppStoreConnectCredentialError)
}
