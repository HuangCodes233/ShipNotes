import Foundation

/// OpenAI-compatible Chat Completions / Responses client. Uses JSON-object format to
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
    let apiFormat: OpenAIAPIFormat
    private let transport: AIHTTPTransport

    init(
        keychainStore: any AIKeychainStoring = AIKeychainStore(),
        urlSession: URLSession = AIRequestPolicy.ephemeralSession,
        baseURL: URL = OpenAIService.defaultBaseURL,
        model: String = OpenAIService.defaultModel,
        apiFormat: OpenAIAPIFormat = .chatCompletions,
        cachedKey: String? = nil
    ) {
        self.keychainStore = keychainStore
        self.urlSession = urlSession
        self.baseURL = baseURL
        self.model = model.isEmpty ? Self.defaultModel : model
        self.apiFormat = apiFormat
        self.transport = AIHTTPTransport(
            session: urlSession, keychainStore: keychainStore, cachedKey: cachedKey)
    }

    private var chatEndpoint: URL {
        AIEndpointResolver.openAI(from: baseURL, format: apiFormat)
    }

    var isConfigured: Bool {
        transport.isConfigured(provider: .openai)
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
        let content = try OpenAIAPIAdapter.text(from: response, format: apiFormat)
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
        let content = try OpenAIAPIAdapter.text(from: response, format: apiFormat)
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
        let content = try OpenAIAPIAdapter.text(from: response, format: apiFormat)
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
        let content = try OpenAIAPIAdapter.text(from: response, format: apiFormat)
        return AIResponseParsing.restoringOriginalURLs(
            try AIResponseParsing.storeMetadata(fromContent: content), from: metadata)
    }

    // MARK: - HTTP

    private func postChatCompletion(body: [String: Any]) async throws -> [String: Any] {
        try await transport.postJSON(
            url: chatEndpoint,
            body: OpenAIAPIAdapter.requestBody(fromChatBody: body, format: apiFormat),
            provider: .openai,
            headers: { ["Authorization": "Bearer \($0)"] })
    }

}
