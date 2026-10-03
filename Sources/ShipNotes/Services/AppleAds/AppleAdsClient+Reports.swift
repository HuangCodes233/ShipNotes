import Foundation

extension AppleAdsClient {
    /// One report query per campaign, a few in flight at a time (serially, a
    /// 100-campaign account took 100 sequential round trips per refresh).
    /// A campaign without a report row had no activity in the range. Its
    /// currency is left empty for the caller to fill from the campaign rather
    /// than assumed to be USD.
    func queryCampaignReports(
        campaignIds: [String], start: String, end: String
    ) async throws -> [AppleAdsCampaignMetrics] {
        guard !campaignIds.isEmpty else { return [] }
        // Unstructured tasks, not a TaskGroup (see mapConcurrently): the
        // macOS 27.2 beta runtime crashed in TaskGroup::offer when group
        // teardown raced a completing child. Each campaign captures its own
        // error; the first one is rethrown after every request finishes.
        let outcomes = await mapConcurrently(campaignIds, maxConcurrent: 4) {
            campaignId -> Result<AppleAdsCampaignMetrics, any Error> in
            do {
                return .success(try await queryCampaignReport(campaignId: campaignId, start: start, end: end))
            } catch {
                return .failure(error)
            }
        }
        var metrics: [AppleAdsCampaignMetrics] = []
        for outcome in outcomes {
            switch outcome {
            case .success(let value): metrics.append(value)
            case .failure(let error): throw error
            }
        }
        return metrics
    }

    private func queryCampaignReport(
        campaignId: String, start: String, end: String
    ) async throws -> AppleAdsCampaignMetrics {
        let body = AppleAdsQueryBody(
            filters: [
                .init(field: "campaignId", operator: "EQUALS", value: filterValue(campaignId))
            ],
            pagination: nil,
            sorting: nil,
            timeRange: AppleAdsTimeRange(
                start: start,
                end: end,
                timeZone: "UTC",
                granularity: "DAILY"
            )
        )
        let list = try await post(
            AppleAdsListResult<AdsReportRowDTO>.self, path: "reports/apps/campaigns/query", body: body)
        if let row = list.extracted.first {
            return row.asMetrics(campaignId: campaignId)
        }
        return AppleAdsCampaignMetrics(
            campaignId: campaignId,
            spend: 0,
            taps: 0,
            impressions: 0,
            installs: 0,
            currency: ""
        )
    }

    func querySearchTerms(campaignId: String, start: String, end: String) async throws -> [AppleAdsSearchTerm] {
        let body = AppleAdsQueryBody(
            filters: [
                .init(field: "campaignId", operator: "EQUALS", value: filterValue(campaignId))
            ],
            pagination: .init(offset: 0, pageSize: 50),
            sorting: nil,
            timeRange: AppleAdsTimeRange(
                start: start,
                end: end,
                timeZone: "ORTZ",
                granularity: "DAILY"
            )
        )
        let list = try await post(
            AppleAdsListResult<AdsSearchTermRowDTO>.self, path: "reports/apps/searchterms/query", body: body)
        return list.extracted.enumerated().map { index, row in row.asModel(index: index) }
    }
}

struct AdsReportRowDTO: Decodable {
    var metadata: AdsCampaignDTO?
    var totalMetrics: AdsMetricsDTO?
    var granularMetrics: [AdsMetricsDTO]?
    /// Reporting-API spellings of the same data (`total`, `granularity`).
    var total: AdsMetricsDTO?
    var granularity: [AdsMetricsDTO]?

    func asMetrics(campaignId: String) -> AppleAdsCampaignMetrics {
        let rows = granularMetrics ?? granularity
        let metrics =
            totalMetrics ?? total
            ?? rows?.reduce(into: AdsMetricsDTO()) { partial, row in
                partial.merge(row)
            }
        return AppleAdsCampaignMetrics(
            campaignId: metadata?.id?.value ?? campaignId,
            spend: metrics?.spendValue ?? 0,
            taps: metrics?.taps ?? 0,
            impressions: metrics?.impressions ?? 0,
            installs: metrics?.installsValue ?? 0,
            currency: metrics?.spendCurrency ?? ""
        )
    }
}

struct AdsMetricsDTO: Decodable {
    var localSpend: AdsMoneyDTO?
    var spend: AdsMoneyDTO?
    var taps: Int?
    var impressions: Int?
    var installs: Int?
    var totalInstalls: Int?

    init(
        localSpend: AdsMoneyDTO? = nil,
        spend: AdsMoneyDTO? = nil,
        taps: Int? = nil,
        impressions: Int? = nil,
        installs: Int? = nil,
        totalInstalls: Int? = nil
    ) {
        self.localSpend = localSpend
        self.spend = spend
        self.taps = taps
        self.impressions = impressions
        self.installs = installs
        self.totalInstalls = totalInstalls
    }

    var spendValue: Double {
        Double(localSpend?.amount ?? spend?.amount ?? "0") ?? 0
    }

    var spendCurrency: String? {
        localSpend?.currency ?? spend?.currency
    }

    var installsValue: Int {
        installs ?? totalInstalls ?? 0
    }

    mutating func merge(_ other: AdsMetricsDTO) {
        taps = (taps ?? 0) + (other.taps ?? 0)
        impressions = (impressions ?? 0) + (other.impressions ?? 0)
        installs = (installs ?? 0) + (other.installs ?? 0)
        totalInstalls = (totalInstalls ?? 0) + (other.totalInstalls ?? 0)
        let combined = spendValue + other.spendValue
        localSpend = AdsMoneyDTO(amount: String(combined), currency: spendCurrency)
    }
}

struct AdsSearchTermRowDTO: Decodable {
    var metadata: AdsSearchTermMetaDTO?
    var totalMetrics: AdsMetricsDTO?
    var total: AdsMetricsDTO?
    var searchTermText: String?
    var searchTermSource: String?

    /// Rows can share a term (different sources) or have no text at all, so
    /// the row position keeps list identities unique.
    func asModel(index: Int) -> AppleAdsSearchTerm {
        let text = metadata?.searchTermText ?? searchTermText ?? ""
        let metrics = totalMetrics ?? total
        return AppleAdsSearchTerm(
            id: "\(index)|\(text)",
            text: text,
            source: metadata?.searchTermSource ?? searchTermSource,
            taps: metrics?.taps ?? 0,
            installs: metrics?.installsValue ?? 0,
            spend: metrics?.spendValue ?? 0
        )
    }
}

struct AdsSearchTermMetaDTO: Decodable {
    var searchTermText: String?
    var searchTermSource: String?
}
