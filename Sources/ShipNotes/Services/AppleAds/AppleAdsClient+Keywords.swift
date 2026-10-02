import Foundation

extension AppleAdsClient {
    func queryKeywords(adGroupId: String) async throws -> [AppleAdsKeyword] {
        let body = AppleAdsQueryBody(
            filters: [
                .init(field: "adGroupId", operator: "EQUALS", value: filterValue(adGroupId))
            ],
            pagination: .init(offset: 0, pageSize: 200),
            sorting: nil,
            timeRange: nil
        )
        let list = try await post(AppleAdsListResult<AdsKeywordDTO>.self, path: "keywords/query", body: body)
        return list.extracted.map(\.asModel)
    }

    func queryKeywordSuggestions(adamId: String, seeds: [String]) async throws -> [AppleAdsKeywordSuggestion] {
        let body = AdsKeywordSuggestionBody(
            adamId: Int64(adamId),
            texts: Array(seeds.prefix(20))
        )
        let list = try await post(
            AppleAdsListResult<AdsKeywordSuggestionDTO>.self,
            path: "suggestions/keywords/query",
            body: body
        )
        let fromAPI = list.extracted.map(\.asModel)
        if !fromAPI.isEmpty { return fromAPI }
        // Some accounts return an empty suggestions payload; still surface the
        // local seeds so the user can review them before a bulk create.
        return seeds.map { AppleAdsKeywordSuggestion(text: $0, source: L("From store copy")) }
    }

    func bulkCreateKeywords(adGroupId: String, keywords: [AppleAdsKeywordDraft]) async throws -> Int {
        let body = AdsBulkKeywordCreateBody(
            allowPartialSuccess: true,
            items: keywords.enumerated().map { index, draft in
                AdsBulkKeywordItem(
                    correlationId: index,
                    data: AdsKeywordCreateDTO(
                        adGroupId: Int64(adGroupId),
                        text: draft.text,
                        matchType: draft.matchType,
                        bid: draft.bidAmount.map { AdsMoneyDTO(amount: $0, currency: nil) },
                        status: "ENABLED"
                    )
                )
            }
        )
        let result = try await post(AppleAdsListResult<AdsBulkResultItem>.self, path: "keywords/bulk-create", body: body)
        return try Self.validateBulkKeywordResult(result.extracted, expectedCount: keywords.count)
    }
}

struct AdsKeywordDTO: Decodable {
    var id: AppleAdsFlexibleID?
    var adGroupId: AppleAdsFlexibleID?
    var text: String?
    var matchType: String?
    var status: String?
    var bid: AdsMoneyDTO?
    var bidAmount: AdsMoneyDTO?

    var asModel: AppleAdsKeyword {
        AppleAdsKeyword(
            id: id?.value ?? text ?? UUID().uuidString,
            adGroupId: adGroupId?.value ?? "",
            text: text ?? "",
            matchType: matchType ?? "BROAD",
            status: status ?? "",
            bidAmount: bid?.amount ?? bidAmount?.amount
        )
    }
}

struct AdsKeywordSuggestionDTO: Decodable {
    var text: String?
    var keyword: String?
    var source: String?

    var asModel: AppleAdsKeywordSuggestion {
        AppleAdsKeywordSuggestion(
            text: text ?? keyword ?? "",
            source: source ?? L("Apple suggestion")
        )
    }
}

struct AdsKeywordSuggestionBody: Encodable {
    var adamId: Int64?
    var texts: [String]
}

struct AdsKeywordCreateDTO: Encodable {
    var adGroupId: Int64?
    var text: String
    var matchType: String
    var bid: AdsMoneyDTO?
    var status: String
}

struct AdsBulkKeywordItem: Encodable {
    var correlationId: Int
    var data: AdsKeywordCreateDTO
}

struct AdsBulkKeywordCreateBody: Encodable {
    var allowPartialSuccess: Bool
    var items: [AdsBulkKeywordItem]
}

struct AdsBulkResultItem: Decodable {
    var correlationId: Int?
    var success: Bool?
}


extension AppleAdsClient {
    static func validateBulkKeywordResult(_ items: [AdsBulkResultItem], expectedCount: Int) throws -> Int {
        let succeeded = items.filter { $0.success == true }.count
        guard items.count == expectedCount, succeeded == expectedCount else {
            throw AppleAdsClientError.requestFailed(
                statusCode: 409,
                message: L("Only %d of %d keywords were confirmed created. Refresh the keyword list before retrying.", succeeded, expectedCount)
            )
        }
        return succeeded
    }
}
