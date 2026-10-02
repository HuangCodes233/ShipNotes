import Foundation

enum AIProfileRole: String, CaseIterable, Identifiable, Sendable {
    case text
    case vision

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return L("Text AI")
        case .vision: return L("Vision AI")
        }
    }
}

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case none
    case anthropic
    case openai
    // case gemini      // future
    // case ollama      // future

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return L("None")
        case .anthropic: return "Anthropic Claude"
        case .openai: return "OpenAI"
        }
    }

    var defaultBaseURL: URL {
        switch self {
        case .none: return URL(string: "about:blank")!
        case .anthropic: return URL(string: "https://api.anthropic.com")!
        case .openai: return URL(string: "https://api.openai.com")!
        }
    }

    var defaultModel: String {
        switch self {
        case .none: return ""
        case .anthropic: return "claude-haiku-4-5"
        case .openai: return "gpt-4o-mini"
        }
    }

    func defaultModel(for role: AIProfileRole) -> String {
        switch (self, role) {
        case (.none, _):
            return ""
        case (.anthropic, .text):
            return "claude-haiku-4-5"
        case (.anthropic, .vision):
            return "claude-haiku-4-5"
        case (.openai, .text):
            return "gpt-4o-mini"
        case (.openai, .vision):
            return "gpt-4o-mini"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .none: return ""
        case .anthropic: return "sk-ant-..."
        case .openai: return "sk-..."
        }
    }

    var supportsVisionInput: Bool {
        switch self {
        case .anthropic, .openai: return true
        case .none: return false
        }
    }

    var keychainAccount: String { keychainAccount(for: .text) }
    var baseURLDefaultsKey: String { baseURLDefaultsKey(for: .text) }
    var modelDefaultsKey: String { modelDefaultsKey(for: .text) }

    func keychainAccount(for role: AIProfileRole) -> String {
        switch role {
        case .text: return "shipnotes.ai.\(rawValue)"
        case .vision: return "shipnotes.ai.vision.\(rawValue)"
        }
    }

    func baseURLDefaultsKey(for role: AIProfileRole) -> String {
        switch role {
        case .text: return "shipnotes.ai.\(rawValue).baseURL"
        case .vision: return "shipnotes.ai.vision.\(rawValue).baseURL"
        }
    }

    func modelDefaultsKey(for role: AIProfileRole) -> String {
        switch role {
        case .text: return "shipnotes.ai.\(rawValue).model"
        case .vision: return "shipnotes.ai.vision.\(rawValue).model"
        }
    }
}

enum AIServiceError: Error, LocalizedError, Sendable {
    case notConfigured
    case missingAPIKey
    case authenticationFailed
    case rateLimited
    case modelOverloaded
    case requestRejected(String)
    case invalidResponse(String)
    case networkError(String)
    case tokenLimitExceeded
    case outputTruncated
    case noContentExtracted

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("No AI provider configured. Open Settings → AI to choose one.")
        case .missingAPIKey: return L("AI provider API key not configured.")
        case .authenticationFailed: return L("AI provider rejected the API key.")
        case .rateLimited: return L("AI provider rate limit reached, try again later.")
        case .modelOverloaded: return L("AI model is overloaded, try again in a moment.")
        case .requestRejected(let s): return L("AI provider rejected this request: %@", s)
        case .invalidResponse(let s): return L("AI returned an unexpected response: %@", s)
        case .networkError(let s): return L("Network error talking to AI provider: %@", s)
        case .tokenLimitExceeded: return L("The input text is too large for the AI model's token limit. Please select a shorter text or use a model with a larger context window.")
        case .outputTruncated: return L("The AI's response was cut off before it finished. Try again, or shorten the input.")
        case .noContentExtracted: return L("AI could not extract any release notes from this file.")
        }
    }
}

enum AIRequestPolicy {
    static let requestTimeout: TimeInterval = 240

    /// Shared ephemeral session for AI providers. Uses `.ephemeral` so request
    /// bodies (which may contain the user's project text or screenshots) are
    /// never written to the on-disk URL cache, and no persistent cookies are
    /// kept. Matches the posture already used by `AppStoreConnectClient`.
    static let ephemeralSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        do {
            return try await HTTPRetryPolicy.data(
                for: request,
                session: session,
                shouldRetryHTTP: { statusCode in
                    return statusCode == 429 || statusCode == 503 || statusCode == 529
                },
                shouldRetryURLError: { urlError in
                    return isRetryableNetworkError(urlError)
                }
            )
        } catch let urlError as URLError {
            // Let cancellation surface as itself: wrapping it in networkError
            // would make isCancellation(_) unable to recognize it downstream.
            if urlError.code == .cancelled {
                throw urlError
            }
            throw AIServiceError.networkError(networkMessage(for: urlError))
        }
    }

    /// Reject a response whose generation stopped because it hit `max_tokens`
    /// before finishing. Both Anthropic (`stop_reason: "max_tokens"`) and
    /// OpenAI (`finish_reason: "length"`) signal this; the payload may look
    /// structurally valid while silently missing trailing content.
    static func validateOutputCompleteness(_ json: [String: Any]) throws {
        if (json["stop_reason"] as? String) == "max_tokens" {
            throw AIServiceError.outputTruncated
        }
        if let choices = json["choices"] as? [[String: Any]],
           (choices.first?["finish_reason"] as? String) == "length" {
            throw AIServiceError.outputTruncated
        }
    }

    static func validate(statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200..<300:
            return
        case 400:
            let message = providerErrorMessage(from: data)
            let normalized = message.lowercased()
            if normalized.contains("context_length_exceeded")
                || normalized.contains("context length")
                || normalized.contains("maximum context")
                || normalized.contains("too many tokens")
                || normalized.contains("input is too long")
                || normalized.contains("prompt is too long")
                || normalized.contains("reduce the length") {
                throw AIServiceError.tokenLimitExceeded
            }
            if normalized.contains("considered high risk")
                || normalized.contains("safety policy")
                || normalized.contains("policy violation")
                || normalized.contains("violates policy") {
                throw AIServiceError.requestRejected(message)
            }
            throw AIServiceError.invalidResponse("HTTP 400: \(message)")
        case 401, 403:
            throw AIServiceError.authenticationFailed
        case 413:
            // Payload too large — same user-facing remedy as a context overflow.
            throw AIServiceError.tokenLimitExceeded
        case 429:
            throw AIServiceError.rateLimited
        case 500, 502, 504:
            // Transient server-side failures: distinct from a malformed
            // response so the user knows retrying may help.
            throw AIServiceError.modelOverloaded
        case 503, 529:
            throw AIServiceError.modelOverloaded
        default:
            throw AIServiceError.invalidResponse("HTTP \(statusCode): \(providerErrorMessage(from: data))")
        }
    }

    private static func providerErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                if let message = error["message"] as? String, !message.isEmpty { return message }
                if let type = error["type"] as? String, !type.isEmpty { return type }
            }
            if let message = object["message"] as? String, !message.isEmpty { return message }
        }
        let body = String(data: data.prefix(600), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let body, !body.isEmpty {
            return body
        }
        return "Unknown provider error"
    }

    /// Only failures before the request reached the provider are retried.
    /// A timeout or a connection dropped mid-response may come after the
    /// provider already generated (and billed) the answer; with a 240 s
    /// timeout, retrying those meant up to ~16 minutes of waiting and up to
    /// four paid generations before the user saw an error.
    static func isRetryableNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch URLError.Code(rawValue: nsError.code) {
        case .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }



    static func networkMessage(for error: Error?) -> String {
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain,
               URLError.Code(rawValue: nsError.code) == .timedOut {
                return L(
                    "Request timed out after %d seconds. The AI service may still be processing; ShipNotes retried automatically but did not receive a response.",
                    Int(requestTimeout)
                )
            }
            return error.localizedDescription
        }
        return L("The AI request failed before receiving a response.")
    }
}

/// Common protocol for any AI provider that can do release-notes parsing and
/// translation. Implementations should be Sendable so they can be reused
/// across actors.
protocol AIService: Sendable {
    /// True when the provider is fully configured (e.g., API key present).
    var isConfigured: Bool { get }

    /// Have an LLM extract a `{locale: body}` map from arbitrary release-notes
    /// text — used as a fallback when none of the deterministic parsers can
    /// confidently handle the file. `currentVersion` is the App Store Connect
    /// version the user is currently editing; the AI should extract only that
    /// version's body when the file contains multiple.
    func parseReleaseNotes(
        text: String,
        currentVersion: String?,
        knownRemoteLocales: [String]
    ) async throws -> [String: String]

    /// Translate one locale's release notes into another locale. Optional
    /// glossary preserves brand names / feature names verbatim.
    func translate(
        text: String,
        fromLocale: String,
        toLocale: String,
        glossary: [String: String]
    ) async throws -> String

    /// Extract App Store product-page metadata from arbitrary local project
    /// text. Used as a fallback when deterministic store-copy parsers cannot
    /// recognize the user's folder or file layout.
    func parseStoreMetadata(
        text: String,
        defaultLocale: String?,
        knownRemoteLocales: [String],
        appName: String,
        versionString: String?
    ) async throws -> [String: StoreMetadataFields]

    /// Optimize App Store product-page metadata for one locale. The provider
    /// should preserve the app's factual content and keep URL fields unchanged.
    func optimizeStoreMetadata(
        metadata: StoreMetadataFields,
        locale: String,
        appName: String,
        versionString: String?
    ) async throws -> StoreMetadataFields
}

/// Stand-in used when no provider is configured. Every call throws so callers
/// can rely on AppState.aiService being non-optional.
struct UnconfiguredAIService: AIService {
    var isConfigured: Bool { false }

    func parseReleaseNotes(
        text: String,
        currentVersion: String?,
        knownRemoteLocales: [String]
    ) async throws -> [String: String] {
        throw AIServiceError.notConfigured
    }

    func translate(
        text: String,
        fromLocale: String,
        toLocale: String,
        glossary: [String: String]
    ) async throws -> String {
        throw AIServiceError.notConfigured
    }

    func parseStoreMetadata(
        text: String,
        defaultLocale: String?,
        knownRemoteLocales: [String],
        appName: String,
        versionString: String?
    ) async throws -> [String: StoreMetadataFields] {
        throw AIServiceError.notConfigured
    }

    func optimizeStoreMetadata(
        metadata: StoreMetadataFields,
        locale: String,
        appName: String,
        versionString: String?
    ) async throws -> StoreMetadataFields {
        throw AIServiceError.notConfigured
    }
}

struct ScreenshotLocaleAssignment: Hashable, Sendable {
    let assetID: String
    let locale: String
    let confidence: Double?
    let reason: String?
}

protocol ScreenshotVisionAIService: Sendable {
    var isConfigured: Bool { get }

    func classifyScreenshotLocales(
        assets: [ScreenshotAsset],
        knownLocales: [String],
        appName: String?
    ) async throws -> [ScreenshotLocaleAssignment]
}

struct UnconfiguredScreenshotVisionAIService: ScreenshotVisionAIService {
    var isConfigured: Bool { false }

    func classifyScreenshotLocales(
        assets: [ScreenshotAsset],
        knownLocales: [String],
        appName: String?
    ) async throws -> [ScreenshotLocaleAssignment] {
        throw AIServiceError.notConfigured
    }
}
