import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct ScreenshotVisionAssetPayload {
    let asset: ScreenshotAsset
    /// Anonymous ID sent to the provider instead of `asset.id`, which is the
    /// absolute file path (user name and folder layout).
    let promptID: String
    let mediaType: String
    let base64: String
}

private struct ScreenshotVisionAssignmentsResponse: Decodable {
    struct Assignment: Decodable {
        let assetID: String
        let locale: String
        let confidence: Double?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case assetID = "asset_id"
            case locale
            case confidence
            case reason
        }
    }

    let assignments: [Assignment]
}

private enum ScreenshotVisionPayloadBuilder {
    /// Images per request. Larger requests get slow and expensive; every
    /// candidate is still sent, in consecutive batches.
    static let batchSize = 12

    /// Classifies every asset, one batch at a time, and maps the anonymous
    /// prompt IDs in the answers back to asset IDs. Previously only the first
    /// 12 candidates were ever sent, so re-running AI matching paid for the
    /// same 12 again and never reached the rest.
    static func classifyInBatches(
        _ assets: [ScreenshotAsset],
        classify: ([ScreenshotVisionAssetPayload]) async throws -> [ScreenshotLocaleAssignment]
    ) async throws -> [ScreenshotLocaleAssignment] {
        var assignments: [ScreenshotLocaleAssignment] = []
        var batchStart = 0
        while batchStart < assets.count {
            try Task.checkCancellation()
            let batch = assets[batchStart..<min(batchStart + batchSize, assets.count)]
            let payloads = try payloads(from: batch, firstIndex: batchStart)
            let assetIDsByPromptID = Dictionary(uniqueKeysWithValues: payloads.map { ($0.promptID, $0.asset.id) })
            for answer in try await classify(payloads) {
                // Ignore IDs the model invented or echoed from another batch.
                guard let assetID = assetIDsByPromptID[answer.assetID] else { continue }
                assignments.append(
                    ScreenshotLocaleAssignment(
                        assetID: assetID,
                        locale: answer.locale,
                        confidence: answer.confidence,
                        reason: answer.reason
                    ))
            }
            batchStart += batchSize
        }
        return assignments
    }

    static func payloads(
        from assets: ArraySlice<ScreenshotAsset>, firstIndex: Int
    ) throws -> [ScreenshotVisionAssetPayload] {
        try assets.enumerated().map { offset, asset in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let source = CGImageSourceCreateWithURL(asset.url as CFURL, nil),
                let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else {
                throw AIServiceError.invalidResponse("Cannot read image: \(asset.url.lastPathComponent)")
            }
            let destData = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(destData, UTType.jpeg.identifier as CFString, 1, nil)
            else {
                throw AIServiceError.invalidResponse("Cannot encode image")
            }
            CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else {
                throw AIServiceError.invalidResponse("Cannot finalize image")
            }

            return ScreenshotVisionAssetPayload(
                asset: asset,
                promptID: "screenshot-\(firstIndex + offset + 1)",
                mediaType: "image/jpeg",
                base64: destData.base64EncodedString()
            )
        }
    }
}

private enum ScreenshotVisionPrompt {
    static func systemPrompt(knownLocales: [String], appName: String?) -> String {
        """
        You classify App Store screenshots by the language visible in the image.
        Return compact JSON only. Do not include markdown.
        Use only one of these App Store locale codes: \(knownLocales.joined(separator: ", ")).
        First inspect visible UI text in the screenshot and choose the locale that matches that written language.
        Do not require locale codes in folder names or filenames; many users put screenshots in generic folders like upload/iphone-6.5.
        Use folder hints, filenames, and app context only when visible text is missing or ambiguous.
        When several regional locales use the same visible language and the screenshot has no region-specific wording, prefer these shared defaults when available: en-US for English, es-ES for Spanish, fr-FR for French, pt-BR for Portuguese.
        Root-level screenshots are often shared language assets, not region-specific assets.
        App name: \(appName ?? "Unknown")
        JSON schema: {"assignments":[{"asset_id":"...","locale":"en-US","confidence":0.0,"reason":"short"}]}
        """
    }

    static func assetText(_ payload: ScreenshotVisionAssetPayload, index: Int) -> String {
        """
        Asset \(index):
        asset_id: \(payload.promptID)
        relative_path: \(payload.asset.relativePath)
        size: \(payload.asset.size.displayName)
        """
    }
}

struct OpenAIScreenshotVisionAIService: ScreenshotVisionAIService {
    let keychainStore: any AIKeychainStoring
    let urlSession: URLSession
    let baseURL: URL
    let model: String
    private let cachedKey: String?

    init(
        keychainStore: any AIKeychainStoring = AIKeychainStore(),
        urlSession: URLSession = AIRequestPolicy.ephemeralSession,
        baseURL: URL = AIProvider.openai.defaultBaseURL,
        model: String = AIProvider.openai.defaultModel(for: .vision),
        cachedKey: String? = nil
    ) {
        self.keychainStore = keychainStore
        self.urlSession = urlSession
        self.baseURL = baseURL
        self.model = model.isEmpty ? AIProvider.openai.defaultModel(for: .vision) : model
        self.cachedKey = cachedKey?.isEmpty == false ? cachedKey : nil
    }

    var isConfigured: Bool {
        if let cachedKey, !cachedKey.isEmpty { return true }
        guard let key = try? keychainStore.load(for: .openai, role: .vision) else { return false }
        return !key.isEmpty
    }

    func classifyScreenshotLocales(
        assets: [ScreenshotAsset],
        knownLocales: [String],
        appName: String?
    ) async throws -> [ScreenshotLocaleAssignment] {
        try await ScreenshotVisionPayloadBuilder.classifyInBatches(assets) { payloads in
            try await classifyBatch(payloads, knownLocales: knownLocales, appName: appName)
        }
    }

    private func classifyBatch(
        _ payloads: [ScreenshotVisionAssetPayload],
        knownLocales: [String],
        appName: String?
    ) async throws -> [ScreenshotLocaleAssignment] {
        var content: [[String: Any]] = [
            ["type": "text", "text": ScreenshotVisionPrompt.systemPrompt(knownLocales: knownLocales, appName: appName)]
        ]
        for (index, payload) in payloads.enumerated() {
            content.append(["type": "text", "text": ScreenshotVisionPrompt.assetText(payload, index: index + 1)])
            content.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:\(payload.mediaType);base64,\(payload.base64)",
                    "detail": "low",
                ],
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "user", "content": content]
            ],
        ]
        let data = try await post(body: body)
        let contentText = try Self.extractContent(data)
        return try Self.parseAssignments(contentText)
    }

    private func post(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: AIEndpointResolver.openAIChatCompletions(from: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = AIRequestPolicy.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try resolveAPIKey())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await AIRequestPolicy.data(for: request, session: urlSession)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse("Non-HTTP response")
        }
        try Self.validate(statusCode: http.statusCode, data: data)
        return data
    }

    private func resolveAPIKey() throws -> String {
        if let cachedKey, !cachedKey.isEmpty { return cachedKey }
        guard let key = try keychainStore.load(for: .openai, role: .vision), !key.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        return key
    }

    private static func extractContent(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content else {
            throw AIServiceError.invalidResponse("Vision response has no content")
        }
        return content
    }
}

struct AnthropicScreenshotVisionAIService: ScreenshotVisionAIService {
    let keychainStore: any AIKeychainStoring
    let urlSession: URLSession
    let baseURL: URL
    let model: String
    private let cachedKey: String?

    init(
        keychainStore: any AIKeychainStoring = AIKeychainStore(),
        urlSession: URLSession = AIRequestPolicy.ephemeralSession,
        baseURL: URL = AIProvider.anthropic.defaultBaseURL,
        model: String = AIProvider.anthropic.defaultModel(for: .vision),
        cachedKey: String? = nil
    ) {
        self.keychainStore = keychainStore
        self.urlSession = urlSession
        self.baseURL = baseURL
        self.model = model.isEmpty ? AIProvider.anthropic.defaultModel(for: .vision) : model
        self.cachedKey = cachedKey?.isEmpty == false ? cachedKey : nil
    }

    var isConfigured: Bool {
        if let cachedKey, !cachedKey.isEmpty { return true }
        guard let key = try? keychainStore.load(for: .anthropic, role: .vision) else { return false }
        return !key.isEmpty
    }

    func classifyScreenshotLocales(
        assets: [ScreenshotAsset],
        knownLocales: [String],
        appName: String?
    ) async throws -> [ScreenshotLocaleAssignment] {
        try await ScreenshotVisionPayloadBuilder.classifyInBatches(assets) { payloads in
            try await classifyBatch(payloads, knownLocales: knownLocales, appName: appName)
        }
    }

    private func classifyBatch(
        _ payloads: [ScreenshotVisionAssetPayload],
        knownLocales: [String],
        appName: String?
    ) async throws -> [ScreenshotLocaleAssignment] {
        var content: [[String: Any]] = []
        for (index, payload) in payloads.enumerated() {
            content.append(["type": "text", "text": ScreenshotVisionPrompt.assetText(payload, index: index + 1)])
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": payload.mediaType,
                    "data": payload.base64,
                ],
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "temperature": 0,
            "system": [
                [
                    "type": "text",
                    "text": ScreenshotVisionPrompt.systemPrompt(knownLocales: knownLocales, appName: appName),
                    "cache_control": ["type": "ephemeral"],
                ]
            ],
            "messages": [
                ["role": "user", "content": content]
            ],
        ]
        let data = try await post(body: body)
        let contentText = try Self.extractContent(data)
        return try Self.parseAssignments(contentText)
    }

    private func post(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: AIEndpointResolver.anthropicMessages(from: baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = AIRequestPolicy.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try resolveAPIKey(), forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await AIRequestPolicy.data(for: request, session: urlSession)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse("Non-HTTP response")
        }
        try Self.validate(statusCode: http.statusCode, data: data)
        return data
    }

    private func resolveAPIKey() throws -> String {
        if let cachedKey, !cachedKey.isEmpty { return cachedKey }
        guard let key = try keychainStore.load(for: .anthropic, role: .vision), !key.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        return key
    }

    private static func extractContent(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct ContentBlock: Decodable {
                let type: String
                let text: String?
            }
            let content: [ContentBlock]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let text = response.content.first(where: { $0.type == "text" })?.text else {
            throw AIServiceError.invalidResponse("Vision response has no text content")
        }
        return text
    }
}

private extension ScreenshotVisionAIService {
    static func parseAssignments(_ content: String) throws -> [ScreenshotLocaleAssignment] {
        let data = try Self.jsonData(from: content)
        // Wrap decoding failures in AIServiceError.invalidResponse so users
        // see a readable message instead of a raw DecodingError description.
        let decoded: ScreenshotVisionAssignmentsResponse
        do {
            decoded = try JSONDecoder().decode(ScreenshotVisionAssignmentsResponse.self, from: data)
        } catch {
            throw AIServiceError.invalidResponse("Vision response could not be parsed: \(error.localizedDescription)")
        }
        return decoded.assignments.map {
            ScreenshotLocaleAssignment(
                assetID: $0.assetID,
                locale: $0.locale,
                confidence: $0.confidence,
                reason: $0.reason
            )
        }
    }

    static func validate(statusCode: Int, data: Data) throws {
        try AIRequestPolicy.validate(statusCode: statusCode, data: data)
    }

    static func jsonData(from content: String) throws -> Data {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
            (try? JSONDecoder().decode(ScreenshotVisionAssignmentsResponse.self, from: data)) != nil
        {
            return data
        }
        guard let start = trimmed.firstIndex(of: "{"),
            let end = trimmed.lastIndex(of: "}"),
            start <= end
        else {
            throw AIServiceError.invalidResponse("Vision response did not contain JSON")
        }
        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8) else {
            throw AIServiceError.invalidResponse("Vision response is not UTF-8")
        }
        return data
    }
}
