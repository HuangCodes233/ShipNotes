import Foundation

extension AppleAdsClient {
    func fetchMe() async throws -> AppleAdsUser {
        let dto = try await get(AdsMeDTO.self, path: "me", scoped: false)
        return AppleAdsUser(userId: dto.userId?.value ?? dto.id?.value ?? "", orgId: dto.orgId?.value)
    }

    func fetchACLs() async throws -> [AppleAdsACL] {
        let list = try await get(AppleAdsListResult<AdsACLDTO>.self, path: "acls", scoped: false)
        return list.extracted.map(\.asModel)
    }

    func fetchAdAccount(id: String) async throws -> AppleAdsAccount {
        let dto = try await get(AdsAccountDTO.self, path: "ad-accounts/\(id)", scoped: true)
        return dto.asModel
    }

    func queryCampaigns(adamId: String) async throws -> [AppleAdsCampaign] {
        let body = AppleAdsQueryBody(
            filters: [
                .init(field: "promotedObjectType", operator: "EQUALS", value: .string("APPSTORE_APP")),
                .init(field: "promotedObjectId", operator: "EQUALS", value: .string(adamId))
            ],
            pagination: .init(offset: 0, pageSize: 100),
            sorting: nil,
            timeRange: nil
        )
        let list = try await post(AppleAdsListResult<AdsCampaignDTO>.self, path: "campaigns/query", body: body)
        return list.extracted.map(\.asModel)
    }

    func queryAdGroups(campaignId: String) async throws -> [AppleAdsAdGroup] {
        let body = AppleAdsQueryBody(
            filters: [
                .init(field: "campaignId", operator: "EQUALS", value: filterValue(campaignId))
            ],
            pagination: .init(offset: 0, pageSize: 100),
            sorting: nil,
            timeRange: nil
        )
        let list = try await post(AppleAdsListResult<AdsAdGroupDTO>.self, path: "adgroups/query", body: body)
        return list.extracted.map(\.asModel)
    }

    func updateCampaignStatus(id: String, status: String) async throws -> AppleAdsCampaign {
        let dto = try await put(
            AdsCampaignDTO.self,
            path: "campaigns/\(id)",
            body: AdsCampaignStatusBody(status: status)
        )
        return dto.asModel
    }

    func checkAppEligibility(adamId: String, countries: [String]) async throws -> AppleAdsEligibility {
        guard !countries.isEmpty else { throw AppleAdsClientError.invalidResponse }
        for country in countries {
            let body = AppleAdsQueryBody(
                filters: [
                    .init(field: "adamId", operator: "EQUALS", value: filterValue(adamId)),
                    .init(field: "supplyPlacement", operator: "EQUALS", value: .string("APPSTORE_SEARCH_RESULTS")),
                    .init(field: "countryOrRegion", operator: "EQUALS", value: .string(country))
                ],
                pagination: .init(offset: 0, pageSize: 1000),
                sorting: nil,
                timeRange: nil
            )
            let list = try await post(AppleAdsListResult<AdsEligibilityDTO>.self, path: "eligibilities/apps/query", body: body)
            guard !list.extracted.isEmpty else { throw AppleAdsClientError.invalidResponse }
            if let blocked = list.extracted.first(where: { !$0.asModel(adamId: adamId).isEligible }) {
                return blocked.asModel(adamId: adamId)
            }
        }
        return AppleAdsEligibility(adamId: adamId, isEligible: true, reasons: [])
    }

    func fetchAppDetails(adamId: String) async throws -> AppleAdsAppDetails {
        let dto = try await get(AdsAppDetailsDTO.self, path: "apps/\(adamId)", scoped: true)
        return dto.asModel(adamId: adamId)
    }

    func createSearchResultsCampaign(_ request: AppleAdsPromoteRequest) async throws -> AppleAdsCampaign {
        guard AppleAdsPromoteRequest.validAmounts(budget: request.dailyBudget, bid: request.defaultBid) else {
            throw AppleAdsClientError.requestFailed(statusCode: 400, message: "Budget and bid must be positive amounts with at most two decimal places; bid must not exceed budget.")
        }
        let createBody = AdsCampaignCreateBody(
            name: request.name,
            adAccountId: Int64(adAccountId),
            billingEvent: "TAPS",
            promotedObjectType: "APPSTORE_APP",
            promotedObjectId: request.adamId,
            dailyBudget: AdsMoneyValue(value: AdsMoneyDTO(amount: request.dailyBudget, currency: request.currency)),
            targeting: AdsTargetingBody(
                countryOrRegion: .init(include: request.countries),
                supplyPlacement: .init(include: ["APPSTORE_SEARCH_RESULTS"])
            ),
            bidStrategy: AdsBidStrategyBody(bidStrategyType: "MANUAL_CPT", bidStrategyGoal: "TAP"),
            status: "PAUSED"
        )
        let campaign = try await post(AdsCampaignDTO.self, path: "campaigns", body: createBody).asModel

        do {

        let adGroupBody = AdsAdGroupCreateBody(
            campaignId: Int64(campaign.id),
            name: request.name,
            pricingModel: "CPT",
            bidStrategy: AdsBidStrategyBody(
                bidStrategyType: "MANUAL_CPT",
                bidStrategyGoal: "TAP",
                bid: AdsMoneyDTO(amount: request.defaultBid, currency: request.currency)
            ),
            status: "ENABLED"
        )
        let adGroup = try await post(AdsAdGroupDTO.self, path: "adgroups", body: adGroupBody)

        if !request.keywords.isEmpty, let adGroupId = adGroup.id?.value {
            _ = try await bulkCreateKeywords(
                adGroupId: adGroupId,
                keywords: request.keywords
            )
        }

        let creativeBody = AdsCreativeCreateBody(
            name: "\(request.name) — Default Product Page",
            creativeType: "DEFAULT_PRODUCT_PAGE",
            creativeSpec: [:],
            destination: AdsCreativeDestination(
                destinationType: "APP_STORE_PRODUCT_PAGE",
                parameters: ["adamId": request.adamId]
            )
        )
        let creative = try await post(AdsCreativeDTO.self, path: "creatives", body: creativeBody)
        if let creativeId = creative.id?.value,
           let adGroupId = adGroup.id?.value {
            let adBody = AdsAdCreateBody(
                adGroupId: Int64(adGroupId),
                creativeId: Int64(creativeId),
                name: "Default Search Ad",
                status: "ENABLED"
            )
            _ = try await post(AdsAdDTO.self, path: "ads", body: adBody)
        } else {
            throw AppleAdsClientError.invalidResponse
        }

        // Explicitly leave a completed campaign paused for the user to enable.
        return campaign
        } catch {
            throw AppleAdsClientError.requestFailed(statusCode: 409, message: "Campaign \(campaign.id) was created paused, but setup is incomplete: \(error.localizedDescription). Inspect it in Apple Ads before retrying.")
        }
    }
}

struct AdsCampaignStatusBody: Encodable {
    var status: String
}

struct AdsMeDTO: Decodable {
    var id: AppleAdsFlexibleID?
    var userId: AppleAdsFlexibleID?
    var orgId: AppleAdsFlexibleID?
}

struct AdsACLDTO: Decodable {
    var roles: [String]?
    var roleNames: [String]?
    var adAccount: AdsAccountDTO?
    var account: AdsAccountDTO?
    var adAccountId: AppleAdsFlexibleID?
    var id: AppleAdsFlexibleID?
    var orgId: AppleAdsFlexibleID?
    var orgName: String?
    var name: String?
    var currency: String?
    var timeZone: String?
    var productFeatures: [String]?
    var delegations: [AdsDelegationDTO]?

    var asModel: AppleAdsACL {
        let nested = adAccount ?? account
        let account = nested?.asModel ?? AppleAdsAccount(
            id: nested?.id?.value ?? adAccountId?.value ?? id?.value ?? orgId?.value ?? "",
            name: name ?? orgName ?? L("Apple Ads"),
            orgId: orgId?.value,
            currency: currency ?? "USD",
            timeZone: timeZone,
            productFeatures: productFeatures ?? [],
            hasContentProviderDelegation: delegations?.contains { $0.type == "CONTENT_PROVIDER" } == true
        )
        return AppleAdsACL(roles: roles ?? roleNames ?? [], account: account)
    }
}

struct AdsAccountDTO: Decodable {
    var id: AppleAdsFlexibleID?
    var name: String?
    var orgId: AppleAdsFlexibleID?
    var currency: String?
    var timeZone: String?
    var productFeatures: [String]?
    var delegations: [AdsDelegationDTO]?

    var asModel: AppleAdsAccount {
        AppleAdsAccount(
            id: id?.value ?? "",
            name: name ?? L("Apple Ads"),
            orgId: orgId?.value,
            currency: currency ?? "USD",
            timeZone: timeZone,
            productFeatures: productFeatures ?? [],
            hasContentProviderDelegation: delegations?.contains { $0.type == "CONTENT_PROVIDER" } == true
        )
    }
}

struct AdsDelegationDTO: Decodable {
    var type: String?
    var resourceId: AppleAdsFlexibleID?
}

struct AdsCampaignDTO: Decodable {
    var id: AppleAdsFlexibleID?
    var name: String?
    var status: String?
    var displayStatus: String?
    var promotedObjectId: AppleAdsFlexibleID?
    var adamId: AppleAdsFlexibleID?
    var dailyBudget: AdsMoneyValue?
    var dailyBudgetAmount: AdsMoneyDTO?
    var targeting: AdsTargetingDTO?

    var asModel: AppleAdsCampaign {
        let budget = dailyBudget?.value ?? dailyBudgetAmount
        return AppleAdsCampaign(
            id: id?.value ?? "",
            name: name ?? L("Untitled campaign"),
            status: status ?? "",
            adamId: promotedObjectId?.value ?? adamId?.value ?? "",
            dailyBudgetAmount: budget?.amount,
            dailyBudgetCurrency: budget?.currency,
            supplyPlacement: targeting?.supplyPlacement?.include?.first,
            displayStatus: displayStatus
        )
    }
}

struct AdsAdGroupDTO: Decodable {
    var id: AppleAdsFlexibleID?
    var campaignId: AppleAdsFlexibleID?
    var name: String?
    var status: String?

    var asModel: AppleAdsAdGroup {
        AppleAdsAdGroup(
            id: id?.value ?? "",
            campaignId: campaignId?.value ?? "",
            name: name ?? L("Ad Group"),
            status: status ?? ""
        )
    }
}

struct AdsEligibilityDTO: Decodable {
    var adamId: AppleAdsFlexibleID?
    var state: String?
    var eligible: Bool?
    var isEligible: Bool?
    var reasons: [String]?
    var rejectionReasons: [String]?

    func asModel(adamId fallback: String) -> AppleAdsEligibility {
        AppleAdsEligibility(
            adamId: adamId?.value ?? fallback,
            isEligible: state.map { $0 == "ELIGIBLE" } ?? eligible ?? isEligible ?? false,
            reasons: reasons ?? rejectionReasons ?? []
        )
    }
}

struct AdsAppDetailsDTO: Decodable {
    var adamId: AppleAdsFlexibleID?
    var name: String?
    var displayName: String?
    var appName: String?
    var availableStorefronts: [String]?
    var currency: String?

    func asModel(adamId fallback: String) -> AppleAdsAppDetails {
        AppleAdsAppDetails(
            adamId: adamId?.value ?? fallback,
            name: appName ?? name ?? displayName ?? "",
            availableStorefronts: availableStorefronts ?? [],
            currency: currency
        )
    }
}

struct AdsMoneyDTO: Codable {
    var amount: String?
    var currency: String?
}

struct AdsMoneyValue: Codable {
    var value: AdsMoneyDTO?
}

struct AdsTargetingDTO: Decodable {
    var supplyPlacement: AdsIncludeDTO?
    var countryOrRegion: AdsIncludeDTO?
}

struct AdsIncludeDTO: Codable {
    var include: [String]?
}

struct AdsTargetingBody: Encodable {
    var countryOrRegion: AdsIncludeDTO
    var supplyPlacement: AdsIncludeDTO
}

struct AdsBidStrategyBody: Encodable {
    var bidStrategyType: String
    var bidStrategyGoal: String
    var bid: AdsMoneyDTO?
}

struct AdsCampaignCreateBody: Encodable {
    var name: String
    var adAccountId: Int64?
    var billingEvent: String
    var promotedObjectType: String
    var promotedObjectId: String
    var dailyBudget: AdsMoneyValue
    var targeting: AdsTargetingBody
    var bidStrategy: AdsBidStrategyBody
    var status: String
}

struct AdsAdGroupCreateBody: Encodable {
    var campaignId: Int64?
    var name: String
    var pricingModel: String
    var bidStrategy: AdsBidStrategyBody
    var status: String
}

struct AdsCreativeCreateBody: Encodable {
    var name: String
    var creativeType: String
    var creativeSpec: [String: String]
    var destination: AdsCreativeDestination
}

struct AdsCreativeDestination: Encodable {
    var destinationType: String
    var parameters: [String: String]
}

struct AdsCreativeDTO: Decodable {
    var id: AppleAdsFlexibleID?
}

struct AdsAdCreateBody: Encodable {
    var adGroupId: Int64?
    var creativeId: Int64?
    var name: String
    var status: String
}

struct AdsAdDTO: Decodable {
    var id: AppleAdsFlexibleID?
}
