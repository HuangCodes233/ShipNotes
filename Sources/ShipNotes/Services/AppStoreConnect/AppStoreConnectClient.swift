import Foundation

// Protocol + HTTP core. Domain methods live in `AppStoreConnectClient+*.swift`.
// Helpers here are internal (not `private`) so those extensions can call them —
// `private` is file-scoped and would not be visible across the split.

protocol AppStoreConnectServicing: Sendable {
    func validateCredentials() async throws
    func fetchApps() async throws -> [AppRecord]
    func fetchVersions(appId: String) async throws -> [ReleaseVersion]
    func fetchLocalizations(versionId: String) async throws -> [RemoteLocaleNote]
    func updateWhatsNew(localizationId: String, text: String) async throws -> RemoteLocaleNote
    func updateStoreMetadata(localizationId: String, metadata: StoreMetadataFields) async throws -> RemoteLocaleNote
    func updateStoreMetadataField(
        localizationId: String, field: StoreCopyField, value: String
    ) async throws -> RemoteLocaleNote
    func createLocalization(versionId: String, locale: String, text: String) async throws -> RemoteLocaleNote
    /// Create a new editable App Store version for the given app. `platform`
    /// must be one of Apple's enum values (`IOS`, `MAC_OS`, `TV_OS`, `VISION_OS`).
    func createVersion(appId: String, versionString: String, platform: String) async throws -> ReleaseVersion

    /// List all uploaded builds for the given app that share the given
    /// marketing version (CFBundleShortVersionString). Result sorted newest first.
    func fetchBuilds(appId: String, marketingVersion: String) async throws -> [Build]

    /// List all uploaded builds for the given app across all versions.
    /// Used by NewVersionSheet to show what's available on the server.
    func fetchAllBuilds(appId: String) async throws -> [Build]

    /// Get the build currently attached to the App Store version, or `nil` if
    /// none has been picked yet.
    func fetchAttachedBuild(versionId: String) async throws -> Build?

    /// Attach an uploaded build to an editable App Store version, or pass
    /// `buildId: nil` to detach.
    func setBuild(_ buildId: String?, forVersion versionId: String) async throws

    /// Update mutable attributes on an existing App Store version. Currently
    /// surfaces `releaseType` (`MANUAL` / `AFTER_APPROVAL` / `SCHEDULED`).
    func updateVersion(versionId: String, releaseType: String?) async throws

    /// Replace the screenshots for one localization + App Store display type
    /// with the provided local files. Files are uploaded in the given order.
    /// `onProgress` is called after each file finishes uploading (0-based index, total, fileName).
    @discardableResult
    func replaceScreenshots(
        localizationId: String, displayType: String, files: [URL], onProgress: (@Sendable (Int, Int, String) -> Void)?
    ) async throws -> Int

    /// Fetch current screenshots grouped by App Store display type for one localization.
    func fetchScreenshotSets(localizationId: String) async throws -> [RemoteScreenshotSet]

    /// Walk the modern review-submission flow in one call: create a
    /// submission, attach the version as an item, and PATCH `submitted: true`.
    /// Returns the final submission's state (e.g., "WAITING_FOR_REVIEW").
    func submitForReview(appId: String, versionId: String, platform: String) async throws -> String
}

enum AppStoreConnectClientError: LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case requestFailed(statusCode: Int, message: String)
    case missingLocalizationId(locale: String)
    case invalidUploadOperation(String)
    case screenshotProcessingFailed(String)
    case screenshotDeletionNotConfirmed
    case invalidResponse
    case invalidResponseBody(String)
    case connectionTimedOut
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            L("Invalid App Store Connect API URL: %@", path)
        case .requestFailed(let statusCode, let message):
            "App Store Connect returned \(statusCode): \(message)"
        case .missingLocalizationId(let locale):
            "Cannot sync \(locale) because App Store Connect has no localization ID for it."
        case .invalidUploadOperation(let message):
            "App Store Connect returned an invalid screenshot upload operation: \(message)"
        case .screenshotProcessingFailed(let details):
            "App Store Connect could not process these screenshots:\n\(details)"
        case .screenshotDeletionNotConfirmed:
            L(
                "Old screenshots are still listed in App Store Connect. Upload stopped before adding new screenshots. Refresh and try again."
            )
        case .invalidResponse:
            "App Store Connect returned a response ShipNotes could not read."
        case .invalidResponseBody(let message):
            "App Store Connect returned a response ShipNotes could not parse: \(message)"
        case .connectionTimedOut:
            "App Store Connect connection timed out. Check your network or proxy and try again."
        case .networkError(let message):
            "App Store Connect network error: \(message)"
        }
    }
}

struct AppStoreConnectClient: AppStoreConnectServicing, Sendable {
    static let requestTimeout: TimeInterval = 60
    static let uploadTimeout: TimeInterval = 180
    /// Apple caps a screenshot set at 10 items per display type.
    static let maxScreenshotsPerSet = 10
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    let baseURL = URL(string: "https://api.appstoreconnect.apple.com/v1")!
    let credentials: AppStoreConnectCredentials
    let tokenProvider: JWTTokenProvider
    let session: URLSession
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    init(credentials: AppStoreConnectCredentials, session: URLSession = AppStoreConnectClient.defaultSession) {
        self.credentials = credentials
        self.tokenProvider = JWTTokenProvider(credentials: credentials)
        self.session = session
        let decoder = JSONDecoder()
        // App Store Connect emits dates in several ISO 8601 variants:
        //   "2026-05-19T18:01:23Z"
        //   "2026-05-19T18:01:23.456Z"
        //   "2026-05-19T18:01:23+00:00"
        //   "2026-05-19T18:01:23.456+00:00"
        // Try the four common shapes; fail with a clear message if none match.
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = Self.parseAppStoreConnectDate(str) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse App Store Connect date: \(str)")
        }
        self.decoder = decoder
        self.encoder = JSONEncoder()
    }
}

extension AppStoreConnectClient {
    static func parseAppStoreConnectDate(_ string: String) -> Date? {
        dateParser.parse(string)
    }

    private static let dateParser = AppStoreConnectDateParser()

    func patchRelationship<Body: Encodable>(path: String, body: Body) async throws {
        let url = try makeURL(path: path)
        var request = try await makeRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, urlResponse) = try await performDataRequest(request)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw AppStoreConnectClientError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let message = decodeErrorMessage(from: data)
            throw AppStoreConnectClientError.requestFailed(statusCode: http.statusCode, message: message)
        }
        // 204 No Content is normal; relationship endpoints don't return a body.
    }

    func deleteResource(path: String) async throws {
        let url = try makeURL(path: path)
        var request = try await makeRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, urlResponse) = try await performDataRequest(request)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw AppStoreConnectClientError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let message = decodeErrorMessage(from: data)
            throw AppStoreConnectClientError.requestFailed(statusCode: http.statusCode, message: message)
        }
    }

    func requestCollection<Resource: Decodable & Sendable>(
        _ type: Resource.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        paged: Bool = true
    ) async throws -> [Resource] {
        var url = try makeURL(path: path, queryItems: queryItems)
        var allResources: [Resource] = []
        var pageCount = 0

        while true {
            let request = try await makeRequest(url: url)
            let response = try await send(request, as: ASCCollectionResponse<Resource>.self)
            allResources.append(contentsOf: response.data)
            pageCount += 1

            guard paged, pageCount < 20, let next = response.links?.next, let nextURL = URL(string: next) else {
                return allResources
            }
            url = nextURL
        }
    }

    func requestResource<Resource: Decodable & Sendable, Body: Encodable>(
        _ type: Resource.Type,
        path: String,
        method: String,
        body: Body
    ) async throws -> Resource {
        let url = try makeURL(path: path)
        var request = try await makeRequest(url: url)
        request.httpMethod = method
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let response = try await send(request, as: ASCResourceResponse<Resource>.self)
        return response.data
    }

    func requestWithoutDecoding<Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws {
        let url = try makeURL(path: path)
        var request = try await makeRequest(url: url)
        request.httpMethod = method
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await sendWithoutDecoding(request)
    }

    func send<Response: Decodable & Sendable>(_ request: URLRequest, as type: Response.Type) async throws -> Response {
        let (data, urlResponse) = try await performDataRequest(request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw AppStoreConnectClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = decodeErrorMessage(from: data)
            throw AppStoreConnectClientError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AppStoreConnectClientError.invalidResponseBody(
                decodeFailureMessage(error: error, data: data)
            )
        }
    }

    func sendWithoutDecoding(_ request: URLRequest) async throws {
        let (data, urlResponse) = try await performDataRequest(request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw AppStoreConnectClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = decodeErrorMessage(from: data)
            throw AppStoreConnectClientError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
    }

    func makeRequest(url: URL) async throws -> URLRequest {
        let token = try await tokenProvider.token()
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func performDataRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let method = request.httpMethod ?? "GET"
        do {
            return try await HTTPRetryPolicy.data(
                for: request,
                session: session,
                shouldRetryHTTP: { statusCode in
                    Self.shouldRetry(statusCode: statusCode, method: method)
                },
                shouldRetryURLError: { urlError in
                    Self.shouldRetry(urlError: urlError, method: method)
                }
            )
        } catch let urlError as URLError {
            // Cancellation must keep its identity so callers can distinguish
            // "user cancelled" from a real failure.
            if urlError.code == .cancelled {
                throw urlError
            }
            throw mapNetworkError(urlError)
        }
    }

    /// 429 (rate limit) is always safe to retry — the request was rejected
    /// before processing. 5xx is only retried for idempotent reads/uploads
    /// (GET/PUT); auto-retrying POST/PATCH/DELETE on a 5xx could duplicate a
    /// create, double-submit, or 404 a second delete.
    static func shouldRetry(statusCode: Int, method: String) -> Bool {
        if statusCode == 429 { return true }
        if (500...599).contains(statusCode) {
            return method == "GET" || method == "PUT"
        }
        return false
    }

    /// Transient network failures: retry only idempotent reads/uploads, same
    /// reasoning as the 5xx case.
    static func shouldRetry(urlError: URLError, method: String) -> Bool {
        let transient: Set<URLError.Code> = [
            .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed,
        ]
        guard transient.contains(urlError.code) else { return false }
        return method == "GET" || method == "PUT"
    }

    func mapNetworkError(_ error: URLError) -> AppStoreConnectClientError {
        if error.code == .timedOut {
            return .connectionTimedOut
        }
        return .networkError(error.localizedDescription)
    }

    func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else {
            throw AppStoreConnectClientError.invalidURL(path)
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw AppStoreConnectClientError.invalidURL(path)
        }
        return url
    }

    func decodeErrorMessage(from data: Data) -> String {
        if let response = try? decoder.decode(ASCErrorResponse.self, from: data) {
            let message = response.errors.map(\.displayMessage).filter { !$0.isEmpty }.joined(separator: "\n")
            if !message.isEmpty { return message }
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    func decodeFailureMessage(error: Error, data: Data) -> String {
        var message = error.localizedDescription
        let snippet = String(data: data.prefix(300), encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let snippet, !snippet.isEmpty {
            message += " Body: \(snippet)"
        }
        return message
    }

    func displayPlatform(_ rawValue: String?) -> String {
        switch rawValue {
        case "IOS": "iOS"
        case "MAC_OS": "macOS"
        case "TV_OS": "tvOS"
        case "VISION_OS": "visionOS"
        default: rawValue ?? "App"
        }
    }
}

/// ISO8601DateFormatter is mutable and non-Sendable. Keep the reusable instances
/// private and serialize every access, including concurrent API response decodes.
private final class AppStoreConnectDateParser: @unchecked Sendable {
    private let lock = NSLock()
    private let formatters: [ISO8601DateFormatter] = {
        // withInternetDateTime already includes withColonSeparatorInTimeZone.
        let options: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
        ]
        return options.map { options in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            return formatter
        }
    }()

    func parse(_ string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        for formatter in formatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
