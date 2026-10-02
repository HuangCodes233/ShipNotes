import Foundation

enum HTTPRetryPolicy {
    /// Shared by AI, App Store Connect and Apple Ads: three retries after the
    /// initial request, for at most four attempts on retryable failures.
    static let maxRetries = 3

    static func data(
        for request: URLRequest,
        session: URLSession,
        shouldRetryHTTP: ((Int) -> Bool),
        shouldRetryURLError: ((URLError) -> Bool)
    ) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   attempt < maxRetries,
                   shouldRetryHTTP(http.statusCode) {
                    attempt += 1
                    try await Task.sleep(for: .nanoseconds(retryDelayNanos(attempt: attempt, response: http)))
                    continue
                }
                return (data, response)
            } catch let error as URLError {
                if attempt < maxRetries, shouldRetryURLError(error) {
                    attempt += 1
                    try await Task.sleep(for: .nanoseconds(retryDelayNanos(attempt: attempt, response: nil)))
                    continue
                }
                throw error
            } catch {
                // Non-URLError throws (e.g. CancellationError) are not retryable.
                throw error
            }
        }
    }

    static func retryDelayNanos(attempt: Int, response: HTTPURLResponse?) -> UInt64 {
        if let response, let seconds = delaySeconds(from: response) {
            return UInt64(min(seconds, maxHeaderDelaySeconds) * 1_000_000_000)
        }
        let base = pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...0.5)
        let seconds = min(30.0, base + jitter)
        return UInt64(seconds * 1_000_000_000)
    }

    /// Cap for a server-provided `Retry-After` / `RateLimit-*` value. A server
    /// telling us to wait an hour shouldn't freeze the operation for an hour —
    /// waiting the cap and retrying (likely failing again) surfaces the problem sooner.
    static let maxHeaderDelaySeconds: TimeInterval = 120

    /// Apple Ads 429s may send `Retry-After` or `RateLimit-Reset` /
    /// `RateLimit-Reset-After` instead of the older Search Ads `X-Rate-Limit`.
    private static func delaySeconds(from response: HTTPURLResponse) -> TimeInterval? {
        let headerNames = ["Retry-After", "RateLimit-Reset-After", "RateLimit-Reset"]
        for name in headerNames {
            guard let raw = response.value(forHTTPHeaderField: name)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }
            if let seconds = parseDelaySeconds(raw) {
                return seconds
            }
        }
        return nil
    }

    private static func parseDelaySeconds(_ raw: String) -> TimeInterval? {
        if let seconds = Double(raw), seconds.isFinite, seconds >= 0 {
            // Unix timestamps are much larger than a retry delay in seconds.
            if seconds > 1_000_000_000 {
                let diff = Date(timeIntervalSince1970: seconds).timeIntervalSinceNow
                return diff > 0 ? diff : nil
            }
            return seconds
        }
        if let date = parseRFC1123Date(raw) {
            let diff = date.timeIntervalSinceNow
            return diff > 0 ? diff : nil
        }
        return nil
    }

    private static func parseRFC1123Date(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: string)
    }
}
