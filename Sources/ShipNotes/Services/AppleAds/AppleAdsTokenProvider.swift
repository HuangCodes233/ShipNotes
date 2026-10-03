import CryptoKit
import Foundation

/// Signs an Apple Ads OAuth client-secret JWT and exchanges it for a Bearer token.
/// This is not the App Store Connect JWT: Ads uses `aud=https://appleid.apple.com`
/// and the JWT is a `client_secret`, not the API Authorization header.
actor AppleAdsTokenProvider: Sendable {
    let credentials: AppleAdsCredentials
    private let session: URLSession
    private var cachedAccessToken: String?
    private var accessTokenExpiration: Date?

    init(
        credentials: AppleAdsCredentials,
        session: URLSession = AppleAdsTokenProvider.defaultSession
    ) {
        self.credentials = credentials
        self.session = session
    }

    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func clientSecretJWT(now: Date = Date(), lifetime: TimeInterval = 24 * 60 * 60) throws -> String {
        let creds = try credentials.validated()
        let issuedAt = Int(now.timeIntervalSince1970)
        let expiresAt = Int(now.addingTimeInterval(min(lifetime, 180 * 24 * 60 * 60)).timeIntervalSince1970)
        let header = AdsJWTHeader(kid: creds.keyId)
        let payload = AdsJWTPayload(
            iss: creds.teamId,
            sub: creds.clientId,
            iat: issuedAt,
            exp: expiresAt
        )

        let headerData = try JSONEncoder.adsJWT.encode(header)
        let payloadData = try JSONEncoder.adsJWT.encode(payload)
        let signingInput = "\(headerData.base64URLEncodedString()).\(payloadData.base64URLEncodedString())"
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: normalizePEM(creds.privateKeyPEM))
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(signature.rawRepresentation.base64URLEncodedString())"
    }

    func accessToken(now: Date = Date()) async throws -> String {
        if let token = cachedAccessToken,
            let exp = accessTokenExpiration,
            exp.timeIntervalSince(now) > 60
        {
            return token
        }

        let creds = try credentials.validated()
        let secret = try clientSecretJWT(now: now)
        var request = URLRequest(url: URL(string: "https://appleid.apple.com/auth/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("appleid.apple.com", forHTTPHeaderField: "Host")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=client_credentials",
            "client_id=\(urlEncoded(creds.clientId))",
            "client_secret=\(urlEncoded(secret))",
            "scope=searchadsorg",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppleAdsClientError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AppleAdsClientError.unauthorized(message)
            }
            throw AppleAdsClientError.requestFailed(statusCode: http.statusCode, message: message)
        }

        let tokenResponse = try JSONDecoder().decode(AppleAdsTokenResponse.self, from: data)
        cachedAccessToken = tokenResponse.accessToken
        accessTokenExpiration = now.addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 3600))
        return tokenResponse.accessToken
    }

    private nonisolated func normalizePEM(_ pem: String) -> String {
        pem
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\n", with: "\n")
    }

    private nonisolated func urlEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private struct AdsJWTHeader: Encodable {
    let alg = "ES256"
    let kid: String
}

private struct AdsJWTPayload: Encodable {
    let iss: String
    let sub: String
    let iat: Int
    let exp: Int
    let aud = "https://appleid.apple.com"
}

private struct AppleAdsTokenResponse: Decodable {
    var accessToken: String
    var expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private extension JSONEncoder {
    static var adsJWT: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
