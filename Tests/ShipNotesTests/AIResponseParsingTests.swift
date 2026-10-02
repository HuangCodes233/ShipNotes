import Testing
@testable import ShipNotes

@Suite("AIResponseParsing")
struct AIResponseParsingTests {
    @Test func localesFromFencedJSON() throws {
        let content = """
        Here you go:
        ```json
        {"locales": {"en-US": "Hello", "ja": "こんにちは"}}
        ```
        """
        let locales = try AIResponseParsing.locales(fromContent: content)
        #expect(locales["en-US"] == "Hello")
        #expect(locales["ja"] == "こんにちは")
    }

    @Test func translationAcceptsTextAlias() throws {
        let translated = try AIResponseParsing.translation(fromContent: #"{"text":"Bonjour"}"#)
        #expect(translated == "Bonjour")
    }

    @Test func storeMetadataReadsSnakeAndCamelKeys() throws {
        let json = """
        {
          "description": "Desc",
          "promotional_text": "Promo",
          "support_url": "https://example.com/support",
          "marketingUrl": "https://example.com"
        }
        """
        let metadata = try AIResponseParsing.storeMetadata(fromContent: json)
        #expect(metadata.description == "Desc")
        #expect(metadata.promotionalText == "Promo")
        #expect(metadata.supportURL == "https://example.com/support")
        #expect(metadata.marketingURL == "https://example.com")
    }

    @Test func jsonObjectSurfacesProviderRejection() {
        do {
            _ = try AIResponseParsing.jsonObject(from: "This request was rejected as high risk.")
            Issue.record("Expected requestRejected")
        } catch let error as AIServiceError {
            guard case .requestRejected = error else {
                Issue.record("Expected requestRejected, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected AIServiceError, got \(error)")
        }
    }
}
