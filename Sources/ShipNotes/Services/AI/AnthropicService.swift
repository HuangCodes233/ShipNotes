import Foundation

/// Anthropic Messages API client. Uses forced tool-use to guarantee
/// structured JSON output, and prompt caching on the system prompt to keep
/// per-call cost negligible (~$0.005 per release-notes file).
struct AnthropicService: AIService {
    static let defaultBaseURL = URL(string: "https://api.anthropic.com")!
    static let defaultModel = "claude-haiku-4-5"

    let keychainStore: any AIKeychainStoring
    let urlSession: URLSession
    /// Base URL of the Anthropic-compatible endpoint. Defaults to
    /// `https://api.anthropic.com`; can be overridden to point at a proxy,
    /// self-hosted gateway (LiteLLM / OneAPI / Helicone), or region-specific host.
    let baseURL: URL
    /// Model name. Claude Haiku 4.5 is plenty smart for parse + translate
    /// and the cheapest first-class Claude.
    let model: String
    /// In-memory copy of the API key passed at construction time. Used to
    /// avoid relying on an immediate Keychain re-read (which can flake on
    /// ad-hoc-signed apps right after a write). Falls back to Keychain when nil.
    private let cachedKey: String?

    init(
        keychainStore: any AIKeychainStoring = AIKeychainStore(),
        urlSession: URLSession = AIRequestPolicy.ephemeralSession,
        baseURL: URL = AnthropicService.defaultBaseURL,
        model: String = AnthropicService.defaultModel,
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

    private var messagesEndpoint: URL {
        AIEndpointResolver.anthropicMessages(from: baseURL)
    }

    var isConfigured: Bool {
        if let cached = cachedKey, !cached.isEmpty { return true }
        guard let key = try? keychainStore.load(for: .anthropic) else { return false }
        return !key.isEmpty
    }

    private func resolveAPIKey() throws -> String {
        if let cached = cachedKey, !cached.isEmpty { return cached }
        guard let key = try keychainStore.load(for: .anthropic), !key.isEmpty else {
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
        let systemPrompt = AIPrompts.parseSystemPrompt(formatInstructions: """
- If your runtime supports tool use, call the `submit_release_notes` tool.
- Otherwise output EXACTLY one JSON object, with no surrounding prose, \
no markdown, and no ``` code fences, matching:
    {"locales": {"<locale_code>": "<release notes body>", ...}}
- Return a map of App Store Connect locale code → release-notes body text.
""")
        let userPrompt = AIPrompts.parseUserPrompt(
            text: text,
            currentVersion: currentVersion,
            knownRemoteLocales: knownRemoteLocales
        )

        let toolSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "locales": [
                    "type": "object",
                    "description": "Map of App Store Connect locale code (e.g., 'en-US', 'zh-Hans', 'ja') to the release-notes body for that locale.",
                    "additionalProperties": ["type": "string"]
                ]
            ],
            "required": ["locales"]
        ]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "temperature": 0,
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "tools": [
                [
                    "name": "submit_release_notes",
                    "description": "Submit the extracted release notes, keyed by App Store Connect locale code.",
                    "input_schema": toolSchema
                ]
            ],
            "tool_choice": ["type": "tool", "name": "submit_release_notes"],
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]

        let response = try await postMessages(body: body)
        let locales = try Self.extractLocalesFromToolUse(response)
        guard !locales.isEmpty else { throw AIServiceError.noContentExtracted }
        return locales
    }

    // MARK: - translate

    func translate(
        text: String,
        fromLocale: String,
        toLocale: String,
        glossary: [String: String]
    ) async throws -> String {
        let systemPrompt = AIPrompts.translateSystemPrompt(formatInstructions: """
- If your runtime supports tool use, call the `submit_translation` tool.
- Otherwise output EXACTLY one JSON object, with no surrounding prose, \
no markdown, and no ``` code fences:
    {"translated_text": "<the translated body>"}
- Return ONLY the translated body. No commentary, no leading "Here is...".
""")
        let userPrompt = AIPrompts.translateUserPrompt(
            text: text,
            fromLocale: fromLocale,
            toLocale: toLocale,
            glossary: glossary
        )

        let toolSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "translated_text": [
                    "type": "string",
                    "description": "The translated release notes in the target locale, preserving line breaks and bullet markers, with no markdown formatting."
                ]
            ],
            "required": ["translated_text"]
        ]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "temperature": 0,
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "tools": [
                [
                    "name": "submit_translation",
                    "description": "Submit the translated release notes text.",
                    "input_schema": toolSchema
                ]
            ],
            "tool_choice": ["type": "tool", "name": "submit_translation"],
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]

        let response = try await postMessages(body: body)
        let translated = try Self.extractTranslationFromToolUse(response)
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
        let systemPrompt = AIPrompts.storeMetadataParseSystemPrompt(formatInstructions: """
- If your runtime supports tool use, call the `submit_store_metadata_locales` tool.
- Otherwise output EXACTLY one JSON object, with no surrounding prose, \
no markdown, and no ``` code fences, matching:
    {"locales": {"<locale_code>": {
      "subtitle": "...",
      "description": "...",
      "keywords": "...",
      "promotionalText": "...",
      "supportURL": "...",
      "marketingURL": "...",
      "privacyPolicyURL": "..."
    }}}
""")
        let userPrompt = AIPrompts.storeMetadataParseUserPrompt(
            text: text,
            defaultLocale: defaultLocale,
            knownRemoteLocales: knownRemoteLocales,
            appName: appName,
            versionString: versionString
        )

        let stringProperty: [String: Any] = ["type": "string"]
        let metadataSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "subtitle": stringProperty,
                "description": stringProperty,
                "keywords": stringProperty,
                "promotionalText": stringProperty,
                "supportURL": stringProperty,
                "marketingURL": stringProperty,
                "privacyPolicyURL": stringProperty
            ]
        ]
        let toolSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "locales": [
                    "type": "object",
                    "description": "Map of App Store Connect locale code to extracted product-page metadata.",
                    "additionalProperties": metadataSchema
                ]
            ],
            "required": ["locales"]
        ]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "temperature": 0,
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "tools": [
                [
                    "name": "submit_store_metadata_locales",
                    "description": "Submit extracted App Store metadata keyed by App Store Connect locale code.",
                    "input_schema": toolSchema
                ]
            ],
            "tool_choice": ["type": "tool", "name": "submit_store_metadata_locales"],
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]

        let response = try await postMessages(body: body)
        let locales = try Self.extractStoreMetadataLocalesFromToolUse(response)
        guard !locales.isEmpty else { throw AIServiceError.noContentExtracted }
        return locales
    }

    // MARK: - optimizeStoreMetadata

    func optimizeStoreMetadata(
        metadata: StoreMetadataFields,
        locale: String,
        appName: String,
        versionString: String?
    ) async throws -> StoreMetadataFields {
        let systemPrompt = AIPrompts.storeMetadataSystemPrompt(formatInstructions: """
- If your runtime supports tool use, call the `submit_store_metadata` tool.
- Otherwise output EXACTLY one JSON object, with no surrounding prose, no markdown, and no ``` code fences:
    {"subtitle":"...","description":"...","keywords":"...","promotionalText":"...","supportURL":"...","marketingURL":"...","privacyPolicyURL":"..."}
""")
        let userPrompt = AIPrompts.storeMetadataUserPrompt(
            metadata: metadata,
            locale: locale,
            appName: appName,
            versionString: versionString
        )

        let stringProperty: [String: Any] = ["type": "string"]
        let toolSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "subtitle": stringProperty,
                "description": stringProperty,
                "keywords": stringProperty,
                "promotionalText": stringProperty,
                "supportURL": stringProperty,
                "marketingURL": stringProperty,
                "privacyPolicyURL": stringProperty
            ],
            "required": ["description", "keywords", "promotionalText", "supportURL", "marketingURL"]
        ]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "temperature": 0,
            "system": [
                [
                    "type": "text",
                    "text": systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "tools": [
                [
                    "name": "submit_store_metadata",
                    "description": "Submit optimized App Store metadata fields.",
                    "input_schema": toolSchema
                ]
            ],
            "tool_choice": ["type": "tool", "name": "submit_store_metadata"],
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]

        let response = try await postMessages(body: body)
        var optimized = try Self.extractStoreMetadataFromToolUse(response)
        optimized.supportURL = metadata.supportURL
        optimized.marketingURL = metadata.marketingURL
        optimized.privacyPolicyURL = metadata.privacyPolicyURL
        return optimized
    }

    // MARK: - HTTP

    private func postMessages(body: [String: Any]) async throws -> [String: Any] {
        let apiKey = try resolveAPIKey()

        var request = URLRequest(url: messagesEndpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
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

    // MARK: - Tool-use parsing

    private static func extractLocalesFromToolUse(_ response: [String: Any]) throws -> [String: String] {
        let toolInput = try extractToolInput(response, expectedName: "submit_release_notes")
        return try AIResponseParsing.locales(from: toolInput)
    }

    private static func extractTranslationFromToolUse(_ response: [String: Any]) throws -> String {
        let toolInput = try extractToolInput(response, expectedName: "submit_translation")
        return try AIResponseParsing.translation(from: toolInput)
    }

    private static func extractStoreMetadataFromToolUse(_ response: [String: Any]) throws -> StoreMetadataFields {
        let toolInput = try extractToolInput(response, expectedName: "submit_store_metadata")
        return AIResponseParsing.storeMetadata(from: toolInput)
    }

    private static func extractStoreMetadataLocalesFromToolUse(_ response: [String: Any]) throws -> [String: StoreMetadataFields] {
        let toolInput = try extractToolInput(response, expectedName: "submit_store_metadata_locales")
        return try AIResponseParsing.storeMetadataLocales(from: toolInput)
    }

    /// Exposed for test fixtures that supply a synthesised response payload.
    static func testHook_extractToolInput(_ response: [String: Any], expectedName: String) throws -> [String: Any] {
        try extractToolInput(response, expectedName: expectedName)
    }

    private static func extractToolInput(_ response: [String: Any], expectedName: String) throws -> [String: Any] {
        // 1. Anthropic-shaped response: { content: [{ type: "tool_use", ... }] }
        if let content = response["content"] as? [[String: Any]] {
            // 1a. Proper Anthropic tool_use block (official endpoint and good proxies).
            for block in content {
                if block["type"] as? String == "tool_use",
                   block["name"] as? String == expectedName,
                   let input = block["input"] as? [String: Any] {
                    return input
                }
            }
            // 1b. Non-Claude models routed through Anthropic protocol often
            // ignore forced tool_use and emit the structured payload in a
            // plain text block instead.
            for block in content {
                if block["type"] as? String == "text",
                   let text = block["text"] as? String,
                   let json = AIResponseParsing.jsonObjectIfPossible(from: text) {
                    return json
                }
            }
        }

        // 2. OpenAI-shaped response: { choices: [{ message: { content: "..." } }] }
        // Some proxies (LiteLLM with mis-routing, ad-hoc Chinese gateways) reply
        // in OpenAI shape even when called via the Anthropic endpoint.
        if let choices = response["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any] {
            if let textContent = message["content"] as? String,
               let json = AIResponseParsing.jsonObjectIfPossible(from: textContent) {
                return json
            }
            // Some shapes nest the JSON in `tool_calls[].function.arguments`.
            if let toolCalls = message["tool_calls"] as? [[String: Any]],
               let firstCall = toolCalls.first,
               let function = firstCall["function"] as? [String: Any],
               let args = function["arguments"] as? String,
               let json = AIResponseParsing.jsonObjectIfPossible(from: args) {
                return json
            }
        }

        // 3. Surface a useful diagnostic so the user / a future Claude can
        // figure out what the proxy actually returned.
        throw AIServiceError.invalidResponse(diagnosticSnippet(from: response))
    }

    /// Build a one-line summary of the response payload, with the first 240
    /// chars of any text we could find — useful for telling proxies apart.
    private static func diagnosticSnippet(from response: [String: Any]) -> String {
        var collected: [String] = []
        if let content = response["content"] as? [[String: Any]] {
            for block in content {
                if let text = block["text"] as? String {
                    collected.append(text)
                }
            }
        }
        if let choices = response["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let text = message["content"] as? String {
            collected.append(text)
        }
        let topKeys = response.keys.sorted().joined(separator: ", ")
        if collected.isEmpty {
            return "Couldn't extract JSON. Response shape unrecognised. Top-level keys: [\(topKeys)]"
        }
        let snippet = collected.joined(separator: " | ").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = snippet.count > 240 ? String(snippet.prefix(240)) + "…" : snippet
        return "Couldn't extract JSON from model reply. First 240 chars: \(trimmed)"
    }
}
