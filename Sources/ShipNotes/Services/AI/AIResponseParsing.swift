import Foundation

/// Shared decoding of structured AI payloads.
/// OpenAI and Anthropic speak different HTTP shapes, but both eventually
/// produce a JSON object with `locales` / `translated_text` / store-copy fields.
enum AIResponseParsing {
    static func jsonObject(from content: String) throws -> [String: Any] {
        if let json = jsonObjectIfPossible(from: content) {
            return json
        }
        if let rejection = providerRejectionReason(in: content) {
            throw AIServiceError.requestRejected(rejection)
        }
        throw AIServiceError.invalidResponse("Model output is not valid JSON: \(content.prefix(200))")
    }

    /// Best-effort JSON object extraction from free-form model text.
    /// Tries: whole string, ```json fences, then `{` … `}` substring.
    static func jsonObjectIfPossible(from text: String) -> [String: Any]? {
        if let json = tryParse(text) { return json }

        let fenced = #"```(?:json)?\s*\n([\s\S]*?)\n```"#
        if let range = text.range(of: fenced, options: .regularExpression) {
            let chunk = String(text[range])
            let inner = chunk
                .replacingOccurrences(of: #"^```(?:json)?\s*\n"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\n```\s*$"#, with: "", options: .regularExpression)
            if let json = tryParse(inner) { return json }
        }

        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            let candidate = String(text[start...end])
            if let json = tryParse(candidate) { return json }
        }
        return nil
    }

    static func locales(from json: [String: Any]) throws -> [String: String] {
        guard let raw = json["locales"] as? [String: Any] else {
            throw AIServiceError.invalidResponse("Model output JSON missing 'locales' object")
        }
        var result: [String: String] = [:]
        for (key, value) in raw {
            if let str = value as? String, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result[key] = str
            }
        }
        return result
    }

    static func locales(fromContent content: String) throws -> [String: String] {
        try locales(from: jsonObject(from: content))
    }

    static func translation(from json: [String: Any]) throws -> String {
        if let translated = json["translated_text"] as? String {
            return translated
        }
        if let translated = json["text"] as? String {
            return translated
        }
        throw AIServiceError.invalidResponse("Model output JSON missing 'translated_text' field")
    }

    static func translation(fromContent content: String) throws -> String {
        try translation(from: jsonObject(from: content))
    }

    static func storeMetadata(from json: [String: Any]) -> StoreMetadataFields {
        func stringValue(_ keys: [String]) -> String {
            for key in keys {
                if let value = json[key] as? String {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return ""
        }
        return StoreMetadataFields(
            subtitle: stringValue(["subtitle"]),
            description: stringValue(["description"]),
            keywords: stringValue(["keywords"]),
            promotionalText: stringValue(["promotionalText", "promotional_text"]),
            supportURL: stringValue(["supportURL", "supportUrl", "support_url"]),
            marketingURL: stringValue(["marketingURL", "marketingUrl", "marketing_url"]),
            privacyPolicyURL: stringValue(["privacyPolicyURL", "privacyPolicyUrl", "privacy_url", "privacyPolicy"])
        )
    }

    static func storeMetadata(fromContent content: String) throws -> StoreMetadataFields {
        storeMetadata(from: try jsonObject(from: content))
    }

    static func storeMetadataLocales(from json: [String: Any]) throws -> [String: StoreMetadataFields] {
        guard let raw = json["locales"] as? [String: Any] else {
            throw AIServiceError.invalidResponse("Model output JSON missing 'locales' object")
        }
        var result: [String: StoreMetadataFields] = [:]
        for (locale, value) in raw {
            guard let dict = value as? [String: Any] else { continue }
            let metadata = storeMetadata(from: dict)
            if !metadata.isEmpty {
                result[locale] = metadata
            }
        }
        return result
    }

    static func storeMetadataLocales(fromContent content: String) throws -> [String: StoreMetadataFields] {
        try storeMetadataLocales(from: jsonObject(from: content))
    }

    private static func tryParse(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func providerRejectionReason(in content: String) -> String? {
        let normalized = content.lowercased()
        guard normalized.contains("request was rejected")
            || normalized.contains("considered high risk")
            || normalized.contains("high risk")
            || normalized.contains("safety policy")
            || normalized.contains("policy violation")
            || normalized.contains("violates policy") else {
            return nil
        }
        return String(content.prefix(240))
    }
}
