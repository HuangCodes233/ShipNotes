import Foundation

protocol AppleAdsServicing: Sendable {
    func fetchMe() async throws -> AppleAdsUser
    func fetchACLs() async throws -> [AppleAdsACL]
    func fetchAdAccount(id: String) async throws -> AppleAdsAccount
    func queryCampaigns(adamId: String) async throws -> [AppleAdsCampaign]
    func queryAdGroups(campaignId: String) async throws -> [AppleAdsAdGroup]
    func queryCampaignReports(campaignIds: [String], start: String, end: String) async throws -> [AppleAdsCampaignMetrics]
    func queryKeywords(adGroupId: String) async throws -> [AppleAdsKeyword]
    func querySearchTerms(campaignId: String, start: String, end: String) async throws -> [AppleAdsSearchTerm]
    func queryKeywordSuggestions(adamId: String, seeds: [String]) async throws -> [AppleAdsKeywordSuggestion]
    func bulkCreateKeywords(adGroupId: String, keywords: [AppleAdsKeywordDraft]) async throws -> Int
    func checkAppEligibility(adamId: String, countries: [String]) async throws -> AppleAdsEligibility
    func fetchAppDetails(adamId: String) async throws -> AppleAdsAppDetails
    func createSearchResultsCampaign(_ request: AppleAdsPromoteRequest) async throws -> AppleAdsCampaign
    func updateCampaignStatus(id: String, status: String) async throws -> AppleAdsCampaign
}

enum AppleAdsClientError: LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case requestFailed(statusCode: Int, message: String)
    case unauthorized(String)
    case invalidResponse
    case invalidResponseBody(String)
    case connectionTimedOut
    case networkError(String)
    case missingAdAccount
    case sampleDataIsReadOnly

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            L("Invalid Apple Ads API URL: %@", path)
        case .requestFailed(let statusCode, let message):
            "Apple Ads returned \(statusCode): \(message)"
        case .unauthorized(let message):
            L("Apple Ads rejected the credentials: %@", message)
        case .invalidResponse:
            L("Apple Ads returned a response ShipNotes could not read.")
        case .invalidResponseBody(let message):
            L("Apple Ads returned a response ShipNotes could not parse: %@", message)
        case .connectionTimedOut:
            L("Apple Ads connection timed out. Check your network or proxy and try again.")
        case .networkError(let message):
            L("Apple Ads network error: %@", message)
        case .missingAdAccount:
            L("Select an Apple Ads account in Settings.")
        case .sampleDataIsReadOnly:
            L("Connect Apple Ads in Settings before changing live campaigns.")
        }
    }
}

struct AppleAdsClient: AppleAdsServicing, Sendable {
    let baseURL = URL(string: "https://api.ads.apple.com/v1")!

    /// Joins `/v1` with paths that contain slashes (`campaigns/query`).
    /// `appendingPathComponent` would percent-encode the slash and 404.
    static func endpointURL(baseURL: URL, path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { throw AppleAdsClientError.invalidURL(path) }
        return baseURL.appending(path: trimmed)
    }
    let tokenProvider: AppleAdsTokenProvider
    let session: URLSession
    let adAccountId: String
    let decoder = JSONDecoder()
    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    init(
        credentials: AppleAdsCredentials,
        session: URLSession = AppStoreConnectClient.defaultSession,
        tokenSession: URLSession = AppleAdsTokenProvider.defaultSession
    ) throws {
        let validated = try credentials.validated()
        guard let adAccountId = validated.adAccountId, !adAccountId.isEmpty else {
            throw AppleAdsClientError.missingAdAccount
        }
        self.adAccountId = adAccountId
        self.tokenProvider = AppleAdsTokenProvider(credentials: validated, session: tokenSession)
        self.session = session
    }
}

extension AppleAdsClient {
    func get<Result: Decodable>(
        _ type: Result.Type,
        path: String,
        scoped: Bool
    ) async throws -> Result {
        let request = try await makeRequest(path: path, method: "GET", scoped: scoped, body: Optional<AdsEmptyBody>.none)
        return try await send(request, as: type)
    }

    func post<Result: Decodable, Body: Encodable>(
        _ type: Result.Type,
        path: String,
        body: Body,
        scoped: Bool = true
    ) async throws -> Result {
        let request = try await makeRequest(path: path, method: "POST", scoped: scoped, body: body)
        return try await send(request, as: type)
    }

    func put<Result: Decodable, Body: Encodable>(
        _ type: Result.Type,
        path: String,
        body: Body
    ) async throws -> Result {
        let request = try await makeRequest(path: path, method: "PUT", scoped: true, body: body)
        return try await send(request, as: type)
    }

    func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        scoped: Bool,
        body: Body?
    ) async throws -> URLRequest {
        let url = try Self.endpointURL(baseURL: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        let token = try await tokenProvider.accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if scoped {
            request.setValue("adAccountId=\(adAccountId)", forHTTPHeaderField: "X-AP-Context")
        }
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func send<Result: Decodable>(_ request: URLRequest, as type: Result.Type) async throws -> Result {
        let method = request.httpMethod ?? "GET"
        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await HTTPRetryPolicy.data(
                for: request,
                session: session,
                shouldRetryHTTP: { status in
                    if status == 429 { return true }
                    if (500...599).contains(status) {
                        return method == "GET" || method == "PUT" || request.url?.path.contains("/query") == true
                    }
                    return false
                },
                shouldRetryURLError: { error in
                    let transient: Set<URLError.Code> = [
                        .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed
                    ]
                    guard transient.contains(error.code) else { return false }
                    return method == "GET" || method == "PUT" || request.url?.path.contains("/query") == true
                }
            )
        } catch let error as URLError {
            if error.code == .cancelled { throw error }
            if error.code == .timedOut { throw AppleAdsClientError.connectionTimedOut }
            throw AppleAdsClientError.networkError(error.localizedDescription)
        }

        guard let http = urlResponse as? HTTPURLResponse else {
            throw AppleAdsClientError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AppleAdsClientError.unauthorized(decodeErrorMessage(from: data))
        }
        guard 200..<300 ~= http.statusCode else {
            throw AppleAdsClientError.requestFailed(
                statusCode: http.statusCode,
                message: decodeErrorMessage(from: data)
            )
        }

        do {
            let envelope = try decoder.decode(AppleAdsEnvelope<Result>.self, from: data)
            if envelope.success == false {
                throw AppleAdsClientError.requestFailed(
                    statusCode: http.statusCode,
                    message: envelope.error?.message ?? "Apple Ads request failed"
                )
            }
            if let result = envelope.result {
                return result
            }
            return try decoder.decode(Result.self, from: data)
        } catch let error as AppleAdsClientError {
            throw error
        } catch {
            throw AppleAdsClientError.invalidResponseBody(error.localizedDescription)
        }
    }

    func decodeErrorMessage(from data: Data) -> String {
        if let envelope = try? decoder.decode(AppleAdsEnvelope<AdsEmptyResult>.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    func filterValue(_ raw: String) -> AppleAdsJSONScalar {
        if let int = Int64(raw) { return .int(int) }
        return .string(raw)
    }
}

struct AppleAdsEnvelope<Result: Decodable>: Decodable {
    var success: Bool?
    var result: Result?
    var error: AppleAdsAPIErrorBody?

    enum CodingKeys: String, CodingKey {
        case success, result, data, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(AppleAdsAPIErrorBody.self, forKey: .error)
        result = try container.decodeIfPresent(Result.self, forKey: .result)
            ?? container.decodeIfPresent(Result.self, forKey: .data)
    }
}

struct AppleAdsAPIErrorBody: Decodable {
    var code: String?
    var message: String?
}

struct AdsEmptyBody: Encodable {}
struct AdsEmptyResult: Decodable {}

enum AppleAdsJSONScalar: Encodable, Decodable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        }
    }
}

struct AppleAdsFlexibleID: Decodable, Hashable, Sendable {
    var value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int64.self) {
            value = String(int)
        } else {
            value = try container.decode(String.self)
        }
    }
}

struct AppleAdsQueryBody: Encodable {
    var filters: [AppleAdsFilter]
    var pagination: AppleAdsPagination?
    var sorting: [AppleAdsSort]?
    var timeRange: AppleAdsTimeRange?

    struct AppleAdsFilter: Encodable {
        var field: String
        var `operator`: String
        var value: AppleAdsJSONScalar
    }

    struct AppleAdsPagination: Encodable {
        var offset: Int
        var pageSize: Int
    }

    struct AppleAdsSort: Encodable {
        var field: String
        var order: String
    }
}

struct AppleAdsTimeRange: Encodable {
    var start: String
    var end: String
    var timeZone: String
    var granularity: String
}

struct AppleAdsListResult<Item: Decodable>: Decodable {
    var extracted: [Item]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case items, data, acls, campaigns, adGroups, keywords, rows, suggestions, result
    }

    /// Reporting responses nest their rows: `{"reportingDataResponse":{"row":[…]}}`.
    private enum ReportingKeys: String, CodingKey {
        case reportingDataResponse
    }

    private enum ReportingRowKeys: String, CodingKey {
        case row
    }

    init(from decoder: Decoder) throws {
        if let array = try? [Item](from: decoder) {
            extracted = array
            return
        }
        let reporting = try decoder.container(keyedBy: ReportingKeys.self)
        if reporting.contains(.reportingDataResponse) {
            let rows = try reporting.nestedContainer(keyedBy: ReportingRowKeys.self, forKey: .reportingDataResponse)
            extracted = try rows.decodeIfPresent([Item].self, forKey: .row) ?? []
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.allCases {
            if let items = try container.decodeIfPresent([Item].self, forKey: key) {
                extracted = items
                return
            }
        }
        // A known key with a null value is an empty list. A payload with none
        // of them is a shape this decoder doesn't understand: failing is
        // better than showing it as "no campaigns" or $0 spend.
        guard CodingKeys.allCases.contains(where: container.contains) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognized Apple Ads list response"
            ))
        }
        extracted = []
    }
}
