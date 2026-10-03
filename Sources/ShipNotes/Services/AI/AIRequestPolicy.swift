import Foundation

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
            (choices.first?["finish_reason"] as? String) == "length"
        {
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
                || normalized.contains("reduce the length")
            {
                throw AIServiceError.tokenLimitExceeded
            }
            if normalized.contains("considered high risk")
                || normalized.contains("safety policy")
                || normalized.contains("policy violation")
                || normalized.contains("violates policy")
            {
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
                URLError.Code(rawValue: nsError.code) == .timedOut
            {
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
