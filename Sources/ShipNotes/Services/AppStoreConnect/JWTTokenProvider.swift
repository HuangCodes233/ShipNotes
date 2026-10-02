import CryptoKit
import Foundation

actor JWTTokenProvider: Sendable {
    let credentials: AppStoreConnectCredentials
    private var cachedToken: String?
    private var tokenExpiration: Date?

    init(credentials: AppStoreConnectCredentials) {
        self.credentials = credentials
    }

    func token(now: Date = Date(), lifetime: TimeInterval = 19 * 60) throws -> String {
        // Return cached token if it's valid for at least 2 more minutes
        if let token = cachedToken, let exp = tokenExpiration, exp.timeIntervalSince(now) > 120 {
            return token
        }

        let creds = try credentials.validated()
        let issuedAt = Int(now.timeIntervalSince1970)
        let expiresAt = Int(now.addingTimeInterval(lifetime).timeIntervalSince1970)
        let header = JWTHeader(kid: creds.keyId)
        let payload = JWTPayload(iss: creds.issuerId, iat: issuedAt, exp: expiresAt)

        let headerData = try JSONEncoder.jwt.encode(header)
        let payloadData = try JSONEncoder.jwt.encode(payload)
        let signingInput = "\(headerData.base64URLEncodedString()).\(payloadData.base64URLEncodedString())"
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: normalizePEM(creds.privateKeyPEM))
        let signature = try privateKey.signature(for: Data(signingInput.utf8))

        let newToken = "\(signingInput).\(signature.rawRepresentation.base64URLEncodedString())"
        self.cachedToken = newToken
        self.tokenExpiration = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        return newToken
    }

    private nonisolated func normalizePEM(_ pem: String) -> String {
        pem
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\n", with: "\n")
    }
}

private struct JWTHeader: Encodable {
    let alg = "ES256"
    let kid: String
    let typ = "JWT"
}

private struct JWTPayload: Encodable {
    let iss: String
    let iat: Int
    let exp: Int
    let aud = "appstoreconnect-v1"
}

private extension JSONEncoder {
    static var jwt: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
