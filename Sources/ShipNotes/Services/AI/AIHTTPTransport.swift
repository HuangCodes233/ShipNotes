import Foundation

/// Shared POST plumbing for the AI services (text + vision, OpenAI and
/// Anthropic shapes): API-key resolution with the cached-key fallback, request
/// building, the retry policy, status validation, JSON deserialization and
/// truncation checks. A service contributes only the endpoint, its auth
/// headers and the request body.
struct AIHTTPTransport: Sendable {
    let session: URLSession
    let keychainStore: any AIKeychainStoring
    /// In-memory copy of the API key passed at construction time. Ad-hoc-signed
    /// apps can flake on a Keychain re-read right after a write, so callers
    /// pass the key they just saved; falls back to the Keychain when nil.
    private let cachedKey: String?

    init(
        session: URLSession = AIRequestPolicy.ephemeralSession,
        keychainStore: any AIKeychainStoring,
        cachedKey: String? = nil
    ) {
        self.session = session
        self.keychainStore = keychainStore
        self.cachedKey = cachedKey?.isEmpty == false ? cachedKey : nil
    }

    func isConfigured(provider: AIProvider, role: AIProfileRole = .text) -> Bool {
        if cachedKey != nil { return true }
        guard let key = try? keychainStore.load(for: provider, role: role) else { return false }
        return !key.isEmpty
    }

    func resolveAPIKey(provider: AIProvider, role: AIProfileRole = .text) throws -> String {
        if let cachedKey { return cachedKey }
        guard let key = try keychainStore.load(for: provider, role: role), !key.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        return key
    }

    /// POST `body` as JSON and return the decoded response object, after
    /// status and output-completeness validation.
    func postJSON(
        url: URL,
        body: [String: Any],
        provider: AIProvider,
        role: AIProfileRole = .text,
        headers: (String) -> [String: String]
    ) async throws -> [String: Any] {
        let apiKey = try resolveAPIKey(provider: provider, role: role)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AIRequestPolicy.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers(apiKey) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await AIRequestPolicy.data(for: request, session: session)

        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse("Non-HTTP response")
        }
        try AIRequestPolicy.validate(statusCode: http.statusCode, data: data)

        let json: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIServiceError.invalidResponse("Response is not a JSON object")
            }
            json = object
        } catch let error as AIServiceError {
            throw error
        } catch {
            // 2xx with HTML/proxy garbage: surface a readable cause instead of
            // a raw Cocoa error the user can't act on.
            throw AIServiceError.invalidResponse("Response is not JSON: \(error.localizedDescription)")
        }
        try AIRequestPolicy.validateOutputCompleteness(json)
        return json
    }
}
