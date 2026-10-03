import Foundation

/// OpenAI Chat Completions client. Uses JSON-object response format to
/// guarantee parseable structured output. Works with the official OpenAI
/// endpoint and any OpenAI-compatible proxy (LiteLLM, OneAPI, vLLM,
/// LM Studio, Ollama OpenAI API, OpenRouter, Together, Groq, etc.).
struct OpenAIService: AIService {
    static let defaultBaseURL = AIProvider.openai.defaultBaseURL
    static let defaultModel = AIProvider.openai.defaultModel

    let keychainStore: any AIKeychainStoring
    let urlSession: URLSession
    /// Base URL of the OpenAI-compatible endpoint. Defaults to the official
    /// `https://api.openai.com`; can be overridden to point at a proxy
    /// (LiteLLM / OneAPI / OpenRouter / Together / Groq / self-hosted vLLM…).
    let baseURL: URL
    /// Model name. Default `gpt-4o-mini` is OpenAI's cheap workhorse and
    /// supports JSON-object response format on the official endpoint.
    let model: String
    /// See `AnthropicService.cachedKey` — same role: avoid Keychain re-read
    /// flakes right after a write on ad-hoc-signed apps.
    private let cachedKey: String?

    init(
        keychainStore: any AIKeychainStoring = AIKeychainStore(),
        urlSession: URLSession = AIRequestPolicy.ephemeralSession,
        baseURL: URL = OpenAIService.defaultBaseURL,
        model: String = OpenAIService.defaultModel,
        cachedKey: String? = nil
    ) {
        self.keychainStore = keychainStore
        self.urlSession = urlSession
        self.baseURL = baseURL
        self.model = model.isEmpty ? Self.defaultModel : model
        if let cached = cachedKey, !cached.isEmpty {
            self.cachedKey = cached
        } else {
            self.cachedKey = nil
        }
    }

    private var chatEndpoint: URL {
        AIEndpointResolver.openAIChatCompletions(from: baseURL)
    }

    var isConfigured: Bool {
        if let cached = cachedKey, !cached.isEmpty { return true }
        guard let key = try? keychainStore.load(for: .openai) else { return false }
        return !key.isEmpty
    }

    private func resolveAPIKey() throws -> String {
        if let cached = cachedKey, !cached.isEmpty { return cached }
        guard let key = try keychainStore.load(for: .openai), !key.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        return key
    }

    // MARK: - parseReleaseNotes

    func parseReleaseNotes(
        text: String,
        currentVersion: String?,
        knownRemoteLocales: [String]
    ) async throws -> [String: String] {
        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "temperature": 0,
            "messages": [
                [
                    "role": "system",
                    "content": AIPrompts.parseSystemPrompt(
                        formatInstructions: """
                            You MUST respond with a single valid JSON object of the form:
                              {"locales": {"<locale_code>": "<release notes body>", ...}}
                            """),
                ],
                [
                    "role": "user",
                    "content": AIPrompts.parseUserPrompt(
                        text: text,
                        currentVersion: currentVersion,
                        knownRemoteLocales: knownRemoteLocales
                    ),
                ],
            ],
        ]
        let response = try await postChatCompletion(body: body)
        let content = try Self.extractMessageContent(response)
        let parsed = try AIResponseParsing.locales(fromContent: content)
        guard !parsed.isEmpty else { throw AIServiceError.noContentExtracted }
        return parsed
    }

    // MARK: - translate

    func translate(
        text: String,
        fromLocale: String,
        toLocale: String,
        glossary: [String: String]
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "temperature": 0,
            "messages": [
                [
                    "role": "system",
                    "content": AIPrompts.translateSystemPrompt(
                        formatInstructions: """
                            You MUST respond with a single valid JSON object of the form:
                              {"translated_text": "<the translated body>"}
                            """),
                ],
                [
                    "role": "user",
                    "content": AIPrompts.translateUserPrompt(
                        text: text,
                        fromLocale: fromLocale,
                        toLocale: toLocale,
                        glossary: glossary
                    ),
                ],
            ],
        ]
        let response = try await postChatCompletion(body: body)
        let content = try Self.extractMessageContent(response)
        let translated = try AIResponseParsing.translation(fromContent: content)
        guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.noContentExtracted
        }
        return translated
    }

    // MARK: - parseStoreMetadata

    func parseStoreMetadata(
        text: String,
        defaultLocale: String?,
        knownRemoteLocales: [String],
        appName: String,
        versionString: String?
    ) async throws -> [String: StoreMetadataFields] {
        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "temperature": 0,
            "messages": [
                [
                    "role": "system",
                    "content": AIPrompts.storeMetadataParseSystemPrompt(
                        formatInstructions: """
                            You MUST respond with a single valid JSON object of the form:
                              {"locales": {"<locale_code>": {
                                "subtitle": "...",
                                "description": "...",
                                "keywords": "...",
                                "promotionalText": "...",
                                "supportURL": "...",
                                "marketingURL": "...",
                                "privacyPolicyURL": "..."
                              }}}
                            """),
                ],
                [
                    "role": "user",
                    "content": AIPrompts.storeMetadataParseUserPrompt(
                        text: text,
                        defaultLocale: defaultLocale,
                        knownRemoteLocales: knownRemoteLocales,
                        appName: appName,
                        versionString: versionString
                    ),
                ],
            ],
        ]
        let response = try await postChatCompletion(body: body)
        let content = try Self.extractMessageContent(response)
        let parsed = try AIResponseParsing.storeMetadataLocales(fromContent: content)
        guard !parsed.isEmpty else { throw AIServiceError.noContentExtracted }
        return parsed
    }

    // MARK: - optimizeStoreMetadata

    func optimizeStoreMetadata(
        metadata: StoreMetadataFields,
        locale: String,
        appName: String,
        versionString: String?
    ) async throws -> StoreMetadataFields {
        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "temperature": 0.2,
            "messages": [
                [
                    "role": "system",
                    "content": AIPrompts.storeMetadataSystemPrompt(
                        formatInstructions: """
                            You MUST respond with a single valid JSON object:
                            {
                              "subtitle": "...",
                              "description": "...",
                              "keywords": "...",
                              "promotionalText": "...",
                              "supportURL": "...",
                              "marketingURL": "...",
                              "privacyPolicyURL": "..."
                            }
                            """),
                ],
                [
                    "role": "user",
                    "content": AIPrompts.storeMetadataUserPrompt(
                        metadata: metadata,
                        locale: locale,
                        appName: appName,
                        versionString: versionString
                    ),
                ],
            ],
        ]
        let response = try await postChatCompletion(body: body)
        let content = try Self.extractMessageContent(response)
        var optimized = try AIResponseParsing.storeMetadata(fromContent: content)
        // URLs are identity fields for the user's account/web presence. The
        // model can see them for context, but ShipNotes never accepts invented
        // replacements from AI.
        optimized.supportURL = metadata.supportURL
        optimized.marketingURL = metadata.marketingURL
        optimized.privacyPolicyURL = metadata.privacyPolicyURL
        return optimized
    }

    // MARK: - HTTP

    private func postChatCompletion(body: [String: Any]) async throws -> [String: Any] {
        let apiKey = try resolveAPIKey()

        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = AIRequestPolicy.requestTimeout

        let (data, response) = try await AIRequestPolicy.data(for: request, session: urlSession)

        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse("Non-HTTP response")
        }

        try AIRequestPolicy.validate(statusCode: http.statusCode, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.invalidResponse("Response is not JSON")
        }
        try AIRequestPolicy.validateOutputCompleteness(json)
        return json
    }

    // MARK: - Response parsing

    private static func extractMessageContent(_ response: [String: Any]) throws -> String {
        guard let choices = response["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AIServiceError.invalidResponse("Response has no choices[0].message.content")
        }
        return content
    }
}
