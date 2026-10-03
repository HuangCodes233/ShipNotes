import CryptoKit
import Foundation
import Testing
@testable import ShipNotes

@Suite("JWTTokenProvider")
struct JWTTokenProviderTests {
    @Test func createsAppStoreConnectJWTClaims() async throws {
        let key = P256.Signing.PrivateKey()
        let credentials = AppStoreConnectCredentials(
            name: "Test",
            issuerId: "issuer-123",
            keyId: "KEY1234567",
            privateKeyPEM: key.pemRepresentation
        )

        let token = try await JWTTokenProvider(credentials: credentials).token(
            now: Date(timeIntervalSince1970: 1_000),
            lifetime: 600
        )
        let parts = token.split(separator: ".").map(String.init)

        #expect(parts.count == 3)
        let header = try decodeJSONPart(parts[0])
        let payload = try decodeJSONPart(parts[1])

        #expect(header["alg"] as? String == "ES256")
        #expect(header["kid"] as? String == "KEY1234567")
        #expect(header["typ"] as? String == "JWT")
        #expect(payload["iss"] as? String == "issuer-123")
        #expect(payload["aud"] as? String == "appstoreconnect-v1")
        #expect(payload["iat"] as? Int == 1_000)
        #expect(payload["exp"] as? Int == 1_600)
    }

    private func decodeJSONPart(_ value: String) throws -> [String: Any] {
        var base64 =
            value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        let data = try #require(Data(base64Encoded: base64))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
