import Foundation

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
        case .tokenLimitExceeded:
            return L(
                "The input text is too large for the AI model's token limit. Please select a shorter text or use a model with a larger context window."
            )
        case .outputTruncated:
            return L("The AI's response was cut off before it finished. Try again, or shorten the input.")
        case .noContentExtracted: return L("AI could not extract any release notes from this file.")
        }
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
