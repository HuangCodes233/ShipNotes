import Foundation

/// In-memory Apple Ads stand-in used before the user saves an Ads API key.
/// Phase A is read-only against live accounts; sample mode still mutates this
/// in-memory graph so the Ads workspace and promote wizard can be exercised.
final class SampleAppleAdsService: AppleAdsServicing, @unchecked Sendable {
    private var accounts: [AppleAdsAccount]
    private var campaigns: [AppleAdsCampaign]
    private var adGroups: [AppleAdsAdGroup]
    private var keywords: [AppleAdsKeyword]
    private var metrics: [String: AppleAdsCampaignMetrics]
    private var searchTerms: [String: [AppleAdsSearchTerm]]

    init() {
        accounts = [
            AppleAdsAccount(
                id: "sample-ads-1",
                name: "Sample Ads Account",
                orgId: "sample-org",
                currency: "USD",
                timeZone: "UTC",
                productFeatures: ["APPSTORE_APP_MANUAL"],
                hasContentProviderDelegation: true
            )
        ]
        campaigns = [
            AppleAdsCampaign(
                id: "camp-1",
                name: "Example Gallery — Search US",
                status: "ENABLED",
                adamId: "app-1",
                dailyBudgetAmount: "50.00",
                dailyBudgetCurrency: "USD",
                supplyPlacement: "APPSTORE_SEARCH_RESULTS",
                displayStatus: "RUNNING"
            ),
            AppleAdsCampaign(
                id: "camp-2",
                name: "Example Timer — Brand",
                status: "PAUSED",
                adamId: "app-2",
                dailyBudgetAmount: "20.00",
                dailyBudgetCurrency: "USD",
                supplyPlacement: "APPSTORE_SEARCH_RESULTS",
                displayStatus: "PAUSED"
            ),
        ]
        adGroups = [
            AppleAdsAdGroup(id: "ag-1", campaignId: "camp-1", name: "Core keywords", status: "ENABLED"),
            AppleAdsAdGroup(id: "ag-2", campaignId: "camp-2", name: "Brand terms", status: "PAUSED"),
        ]
        keywords = [
            AppleAdsKeyword(
                id: "kw-1", adGroupId: "ag-1", text: "screenshot manager", matchType: "EXACT", status: "ENABLED",
                bidAmount: "1.50"),
            AppleAdsKeyword(
                id: "kw-2", adGroupId: "ag-1", text: "app store screenshots", matchType: "BROAD", status: "ENABLED",
                bidAmount: "1.20"),
            AppleAdsKeyword(
                id: "kw-3", adGroupId: "ag-2", text: "focus timer", matchType: "EXACT", status: "ENABLED",
                bidAmount: "0.90"),
        ]
        metrics = [
            "camp-1": AppleAdsCampaignMetrics(
                campaignId: "camp-1", spend: 128.4, taps: 640, impressions: 18_200, installs: 86, currency: "USD"),
            "camp-2": AppleAdsCampaignMetrics(
                campaignId: "camp-2", spend: 12.0, taps: 40, impressions: 2_100, installs: 4, currency: "USD"),
        ]
        searchTerms = [
            "camp-1": [
                AppleAdsSearchTerm(
                    id: "st-1", text: "screenshot organizer", source: "SEARCH", taps: 42, installs: 9, spend: 18.5),
                AppleAdsSearchTerm(
                    id: "st-2", text: "app preview maker", source: "SEARCH", taps: 11, installs: 1, spend: 4.2),
            ]
        ]
    }

    func fetchMe() async throws -> AppleAdsUser {
        AppleAdsUser(userId: "sample-user", orgId: "sample-org")
    }

    func fetchACLs() async throws -> [AppleAdsACL] {
        accounts.map { AppleAdsACL(roles: ["API Account Read Only"], account: $0) }
    }

    func fetchAdAccount(id: String) async throws -> AppleAdsAccount {
        if let account = accounts.first(where: { $0.id == id }) { return account }
        throw AppleAdsClientError.missingAdAccount
    }

    func queryCampaigns(adamId: String) async throws -> [AppleAdsCampaign] {
        campaigns.filter { $0.adamId == adamId }
    }

    func queryAdGroups(campaignId: String) async throws -> [AppleAdsAdGroup] {
        adGroups.filter { $0.campaignId == campaignId }
    }

    func queryCampaignReports(
        campaignIds: [String], start: String, end: String
    ) async throws -> [AppleAdsCampaignMetrics] {
        _ = start
        _ = end
        return campaignIds.map { id in
            metrics[id]
                ?? AppleAdsCampaignMetrics(
                    campaignId: id,
                    spend: 0,
                    taps: 0,
                    impressions: 0,
                    installs: 0,
                    currency: "USD"
                )
        }
    }

    func queryKeywords(adGroupId: String) async throws -> [AppleAdsKeyword] {
        keywords.filter { $0.adGroupId == adGroupId }
    }

    func querySearchTerms(campaignId: String, start: String, end: String) async throws -> [AppleAdsSearchTerm] {
        _ = start
        _ = end
        return searchTerms[campaignId] ?? []
    }

    func queryKeywordSuggestions(adamId: String, seeds: [String]) async throws -> [AppleAdsKeywordSuggestion] {
        _ = adamId
        let extras = ["ios app", "app store", "mobile app"]
        return (seeds + extras).map { AppleAdsKeywordSuggestion(text: $0, source: L("From store copy")) }
    }

    func bulkCreateKeywords(adGroupId: String, keywords drafts: [AppleAdsKeywordDraft]) async throws -> Int {
        for draft in drafts {
            keywords.append(
                AppleAdsKeyword(
                    id: "kw-\(UUID().uuidString)",
                    adGroupId: adGroupId,
                    text: draft.text,
                    matchType: draft.matchType,
                    status: "ENABLED",
                    bidAmount: draft.bidAmount
                )
            )
        }
        return drafts.count
    }

    func checkAppEligibility(adamId: String, countries: [String]) async throws -> AppleAdsEligibility {
        AppleAdsEligibility(adamId: adamId, isEligible: true, reasons: [])
    }

    func fetchAppDetails(adamId: String) async throws -> AppleAdsAppDetails {
        AppleAdsAppDetails(
            adamId: adamId,
            name: MockAppStoreConnect.sampleApps().first { $0.id == adamId }?.name ?? "App",
            availableStorefronts: ["US", "JP", "CN"],
            currency: "USD"
        )
    }

    func createSearchResultsCampaign(_ request: AppleAdsPromoteRequest) async throws -> AppleAdsCampaign {
        let campaign = AppleAdsCampaign(
            id: "camp-\(UUID().uuidString)",
            name: request.name,
            status: "PAUSED",
            adamId: request.adamId,
            dailyBudgetAmount: request.dailyBudget,
            dailyBudgetCurrency: request.currency,
            supplyPlacement: "APPSTORE_SEARCH_RESULTS",
            displayStatus: "PAUSED"
        )
        campaigns.insert(campaign, at: 0)
        let adGroup = AppleAdsAdGroup(
            id: "ag-\(UUID().uuidString)",
            campaignId: campaign.id,
            name: request.name,
            status: "ENABLED"
        )
        adGroups.append(adGroup)
        _ = try await bulkCreateKeywords(adGroupId: adGroup.id, keywords: request.keywords)
        metrics[campaign.id] = AppleAdsCampaignMetrics(
            campaignId: campaign.id,
            spend: 0,
            taps: 0,
            impressions: 0,
            installs: 0,
            currency: request.currency
        )
        return campaign
    }

    func updateCampaignStatus(id: String, status: String) async throws -> AppleAdsCampaign {
        guard let index = campaigns.firstIndex(where: { $0.id == id }) else {
            throw AppleAdsClientError.invalidResponse
        }
        campaigns[index].status = status
        campaigns[index].displayStatus = status == "ENABLED" ? "RUNNING" : "PAUSED"
        return campaigns[index]
    }
}
