import CryptoKit
import Foundation
import Testing
@testable import ShipNotes

@Suite("Apple Ads")
struct AppleAdsTests {
    @Test func bulkKeywordsDecodeDocumentedArrayAndRejectPartialSuccess() throws {
        let data = Data(#"{"result":[{"correlationId":0,"success":true},{"correlationId":1,"success":false}]}"#.utf8)
        let envelope = try JSONDecoder().decode(AppleAdsEnvelope<AppleAdsListResult<AdsBulkResultItem>>.self, from: data)
        let items = try #require(envelope.result?.extracted)
        #expect(throws: AppleAdsClientError.self) {
            try AppleAdsClient.validateBulkKeywordResult(items, expectedCount: 2)
        }
        #expect(try AppleAdsClient.validateBulkKeywordResult(Array(items.prefix(1)), expectedCount: 1) == 1)
        #expect(throws: AppleAdsClientError.self) {
            try AppleAdsClient.validateBulkKeywordResult([], expectedCount: 1)
        }
    }

    @Test func unrecognizedListPayloadFailsInsteadOfReadingAsEmpty() throws {
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(
                AppleAdsListResult<AdsReportRowDTO>.self,
                from: Data(#"{"report":{"lines":[]}}"#.utf8)
            )
        }
        let explicitlyEmpty = try decoder.decode(AppleAdsListResult<AdsReportRowDTO>.self, from: Data(#"{"data":null}"#.utf8))
        #expect(explicitlyEmpty.extracted.isEmpty)
        let emptyArray = try decoder.decode(AppleAdsListResult<AdsReportRowDTO>.self, from: Data(#"{"data":[]}"#.utf8))
        #expect(emptyArray.extracted.isEmpty)
    }

    @Test func reportingResponseRowsAreDecoded() throws {
        let payload = #"""
        {"data":{"reportingDataResponse":{"row":[
          {"metadata":{"campaignId":1},"total":{"taps":5,"impressions":90,"installs":2,"localSpend":{"amount":"2.50","currency":"EUR"}}}
        ]}}}
        """#
        let envelope = try JSONDecoder().decode(AppleAdsEnvelope<AppleAdsListResult<AdsReportRowDTO>>.self, from: Data(payload.utf8))
        let row = try #require(envelope.result?.extracted.first)
        let metrics = row.asMetrics(campaignId: "1")
        #expect(metrics.taps == 5)
        #expect(metrics.installs == 2)
        #expect(metrics.spend == 2.5)
        #expect(metrics.currency == "EUR")
    }

    @Test func reportRowWithoutSpendDoesNotAssumeUSD() throws {
        let row = try JSONDecoder().decode(AdsReportRowDTO.self, from: Data(#"{"totalMetrics":{"taps":3}}"#.utf8))
        let metrics = row.asMetrics(campaignId: "c-1")
        #expect(metrics.taps == 3)
        #expect(metrics.currency.isEmpty)
    }

    @Test func eligibilityUsesStateAndDoesNotAssumeUnknownMeansEligible() throws {
        for (payload, expected) in [
            (#"{"adamId":123,"state":"ELIGIBLE"}"#, true),
            (#"{"adamId":123,"state":"INELIGIBLE"}"#, false),
            (#"{"adamId":123}"#, false)
        ] {
            let dto = try JSONDecoder().decode(AdsEligibilityDTO.self, from: Data(payload.utf8))
            #expect(dto.asModel(adamId: "123").isEligible == expected)
        }
    }

    @Test func promotionRejectsInvalidAmounts() {
        for value in ["", "abc", "1abc", "0", "-1", "nan", "inf", "1.001"] {
            #expect(!AppleAdsPromoteRequest.validAmounts(budget: value, bid: "1"))
            #expect(!AppleAdsPromoteRequest.validAmounts(budget: "20", bid: value))
        }
        #expect(!AppleAdsPromoteRequest.validAmounts(budget: "1", bid: "2"))
        #expect(AppleAdsPromoteRequest.validAmounts(budget: "20.00", bid: "1.00"))
    }
    @Test func keychainServiceIsSeparateFromAppStoreConnect() {
        #expect(AppleAdsKeychainStore.serviceIdentifier == "org.shipnotes.app.appleads")
        #expect(AppleAdsKeychainStore.serviceIdentifier != "org.shipnotes.app.appstoreconnect")
    }

    @Test func credentialsRequireClientTeamKeyAndPEM() {
        let empty = AppleAdsCredentials(
            name: "Ads",
            clientId: "",
            teamId: "team",
            keyId: "key",
            privateKeyPEM: "pem"
        )
        #expect(throws: AppleAdsCredentialError.missingClientId) {
            try empty.validated()
        }
        #expect(throws: AppleAdsCredentialError.missingTeamId) {
            try AppleAdsCredentials(name: "", clientId: "c", teamId: "", keyId: "k", privateKeyPEM: "p").validated()
        }
        #expect(throws: AppleAdsCredentialError.missingKeyId) {
            try AppleAdsCredentials(name: "", clientId: "c", teamId: "t", keyId: "", privateKeyPEM: "p").validated()
        }
        #expect(throws: AppleAdsCredentialError.missingPrivateKey) {
            try AppleAdsCredentials(name: "", clientId: "c", teamId: "t", keyId: "k", privateKeyPEM: "  ").validated()
        }
    }

    @Test func inMemoryCredentialStoreRoundtrips() throws {
        let store = InMemoryAppleAdsCredentialStore()
        #expect(try store.load() == nil)
        let credentials = AppleAdsCredentials(
            name: "Ads",
            clientId: "SEARCHADS.client",
            teamId: "SEARCHADS.team",
            keyId: "key-id",
            privateKeyPEM: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----",
            adAccountId: "123"
        )
        try store.save(credentials)
        #expect(try store.load() == credentials.trimmed)
        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test func clientSecretJWTUsesAdsOAuthClaims() async throws {
        let key = P256.Signing.PrivateKey()
        let credentials = AppleAdsCredentials(
            name: "Ads",
            clientId: "SEARCHADS.client-id",
            teamId: "SEARCHADS.team-id",
            keyId: "ads-key-id",
            privateKeyPEM: key.pemRepresentation
        )
        let token = try await AppleAdsTokenProvider(credentials: credentials).clientSecretJWT(
            now: Date(timeIntervalSince1970: 1_000),
            lifetime: 600
        )
        let parts = token.split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        let header = try decodeJSONPart(parts[0])
        let payload = try decodeJSONPart(parts[1])

        #expect(header["alg"] as? String == "ES256")
        #expect(header["kid"] as? String == "ads-key-id")
        #expect(payload["iss"] as? String == "SEARCHADS.team-id")
        #expect(payload["sub"] as? String == "SEARCHADS.client-id")
        #expect(payload["aud"] as? String == "https://appleid.apple.com")
        #expect(payload["iat"] as? Int == 1_000)
        #expect(payload["exp"] as? Int == 1_600)
    }

    @Test func endpointURLKeepsQueryPathSlashes() throws {
        let url = try AppleAdsClient.endpointURL(
            baseURL: URL(string: "https://api.ads.apple.com/v1")!,
            path: "campaigns/query"
        )
        #expect(url.absoluteString == "https://api.ads.apple.com/v1/campaigns/query")
        let reports = try AppleAdsClient.endpointURL(
            baseURL: URL(string: "https://api.ads.apple.com/v1")!,
            path: "reports/apps/campaigns/query"
        )
        #expect(reports.absoluteString == "https://api.ads.apple.com/v1/reports/apps/campaigns/query")
    }

    @Test func envelopeAndListDecodeArrayOrWrappedItems() throws {
        let arrayJSON = Data(#"{"success":true,"result":[{"id":"1","name":"US Search","status":"ENABLED"}]}"#.utf8)
        let array = try JSONDecoder().decode(AppleAdsEnvelope<AppleAdsListResult<AdsCampaignDTO>>.self, from: arrayJSON)
        #expect(array.result?.extracted.first?.asModel.name == "US Search")

        let wrappedJSON = Data(#"{"success":true,"result":{"campaigns":[{"id":2,"name":"Brand","promotedObjectId":"111"}]}}"#.utf8)
        let wrapped = try JSONDecoder().decode(AppleAdsEnvelope<AppleAdsListResult<AdsCampaignDTO>>.self, from: wrappedJSON)
        #expect(wrapped.result?.extracted.first?.asModel.adamId == "111")

        let dataJSON = Data(#"{"success":true,"data":[{"id":"acl-1","orgName":"Studio","currency":"USD","roleNames":["ADMIN"]}]}"#.utf8)
        let acls = try JSONDecoder().decode(AppleAdsEnvelope<AppleAdsListResult<AdsACLDTO>>.self, from: dataJSON)
        #expect(acls.result?.extracted.first?.asModel.account.name == "Studio")
    }

    @Test func keywordSeedPullsStoreCopyAndWhatsNew() {
        let phrases = AppleAdsKeywordSeed.phrases(
            keywords: "screenshot manager, app store、release notes",
            whatsNew: """
            • Faster import
            Fix crash on launch
            """,
            appName: "Example Gallery"
        )
        #expect(phrases.contains("screenshot manager"))
        #expect(phrases.contains("app store"))
        #expect(phrases.contains("release notes"))
        #expect(phrases.contains("Faster import"))
        #expect(phrases.contains("Fix crash on launch"))
        #expect(!phrases.contains("Example Gallery"))
    }

    @Test func sampleServiceFiltersCampaignsByAdamId() async throws {
        let service = SampleAppleAdsService()
        let app1 = try await service.queryCampaigns(adamId: "app-1")
        #expect(app1.map(\.id) == ["camp-1"])
        let app3 = try await service.queryCampaigns(adamId: "app-3")
        #expect(app3.isEmpty)
        let reports = try await service.queryCampaignReports(
            campaignIds: ["camp-1"],
            start: "2026-08-01",
            end: "2026-08-07"
        )
        #expect(reports.first?.taps == 640)
        #expect(reports.first?.installs == 86)
    }
}

@Suite("Apple Ads AppState")
@MainActor
struct AppleAdsAppStateTests {
    @Test func failedAdsConnectionKeepsErrorWhenSavingAndTesting() async {
        let store = InMemoryAppleAdsCredentialStore()
        let state = AppState(appleAdsCredentialStore: store, defaults: makeTestDefaults())
        await state.saveAppleAdsCredentials(name: "Invalid", clientId: "client", teamId: "team", keyId: "key", privateKeyPEM: "invalid-pem", adAccountId: "123")
        #expect(state.lastError != nil)
        #expect(state.isUsingSampleAds)
        state.lastError = nil
        await state.testAppleAdsConnection()
        #expect(state.lastError != nil)
    }

    @Test func switchingAppsClearsAdsDraftsAndSelection() async {
        let state = AppState(appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(), defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        await state.refreshAppleAdsForSelectedApp()
        await state.loadAppleAdsKeywordSuggestions()
        state.pendingAppleAdsStatusChange = PendingAppleAdsStatusChange(campaignId: "camp-1", status: "PAUSED")
        state.selectMockApp("app-2")
        #expect(state.appleAdsSuggestions.isEmpty)
        #expect(state.selectedAppleAdsAdGroupId == nil)
        #expect(state.pendingAppleAdsStatusChange == nil)
    }

    @Test func handleErrorClassifiesAdsFailures() {
        let state = AppState(
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            defaults: makeTestDefaults()
        )
        state.handleError(AppleAdsCredentialError.missingClientId)
        #expect(state.lastError?.category == .auth)

        state.handleError(AppleAdsClientError.connectionTimedOut)
        #expect(state.lastError?.category == .network)
        #expect(state.lastError?.isRetryable == true)

        state.handleError(AppleAdsClientError.unauthorized("bad token"))
        #expect(state.lastError?.category == .auth)

        state.handleError(AppleAdsClientError.invalidResponse)
        #expect(state.lastError?.category == .unknown)
    }

    @Test func sampleRefreshLoadsCampaignsAndReportsForSelectedApp() async {
        let state = AppState(
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            defaults: makeTestDefaults()
        )
        state.bootstrapWithMockData()
        await state.refreshAppleAdsForSelectedApp()
        #expect(state.isUsingSampleAds)
        #expect(state.appleAdsCampaigns.map(\.id) == ["camp-1"])
        #expect(state.selectedAppleAdsCampaignId == "camp-1")
        #expect(state.appleAdsMetricsByCampaign["camp-1"]?.installs == 86)
        #expect(state.appleAdsAdGroups.map(\.id) == ["ag-1"])
        #expect(state.appleAdsKeywords.map(\.text).contains("screenshot manager"))
        #expect(state.appleAdsSearchTerms.map(\.text).contains("screenshot organizer"))
    }

    @Test func keywordSuggestionsApplyToSelectedAdGroup() async {
        let state = AppState(
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            defaults: makeTestDefaults()
        )
        state.bootstrapWithMockData()
        await state.refreshAppleAdsForSelectedApp()
        await state.loadAppleAdsKeywordSuggestions()
        #expect(!state.appleAdsSuggestions.isEmpty)
        let before = state.appleAdsKeywords.count
        await state.applySelectedAppleAdsKeywordSuggestions()
        #expect(state.appleAdsKeywords.count > before)
    }

    @Test func pauseAndEnableUpdateSampleCampaign() async {
        let state = AppState(
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            defaults: makeTestDefaults()
        )
        state.bootstrapWithMockData()
        await state.refreshAppleAdsForSelectedApp()
        await state.updateAppleAdsCampaignStatus(id: "camp-1", status: "PAUSED")
        #expect(state.appleAdsCampaigns.first?.status == "PAUSED")
        await state.updateAppleAdsCampaignStatus(id: "camp-1", status: "ENABLED")
        #expect(state.appleAdsCampaigns.first?.isEnabled == true)
    }

    @Test func promoteCreatesSearchResultsCampaign() async {
        let state = AppState(
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            defaults: makeTestDefaults()
        )
        state.bootstrapWithMockData()
        state.selectApp("app-3")
        await state.promoteSelectedVersion(
            AppleAdsPromoteRequest(
                adamId: "app-3",
                name: "ShipNotes Search",
                dailyBudget: "20.00",
                currency: "USD",
                countries: ["US"],
                defaultBid: "1.00",
                keywords: [AppleAdsKeywordDraft(text: "release notes", matchType: "BROAD", bidAmount: "1.00")]
            )
        )
        #expect(state.lastError == nil)
        #expect(state.appleAdsCampaigns.contains { $0.name == "ShipNotes Search" && $0.adamId == "app-3" && $0.status == "PAUSED" })
    }

    @Test func submitOffersPromoteOnlyWhenAdsAreConfigured() async {
        let service = MockASCService()
        let version = ReleaseVersion(
            id: "v-1",
            appId: "app-1",
            versionString: "1.4.0",
            platform: "iOS",
            appStoreState: .prepareForSubmission
        )
        service.fetchedVersions = [version]

        let unconfigured = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            defaults: makeTestDefaults()
        )
        unconfigured.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        unconfigured.versionsByApp["app-1"] = [version]
        unconfigured.selectedAppId = "app-1"
        unconfigured.selectedVersionId = "v-1"
        unconfigured.isUsingMockData = false
        await unconfigured.submitSelectedVersionForReview(releaseType: .afterApproval)
        #expect(unconfigured.offerPromoteAfterSubmit == false)

        let configured = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            appleAdsService: SampleAppleAdsService(),
            defaults: makeTestDefaults()
        )
        configured.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        configured.versionsByApp["app-1"] = [version]
        configured.selectedAppId = "app-1"
        configured.selectedVersionId = "v-1"
        configured.isUsingMockData = false
        configured.appleAdsCredentialSummary = AppleAdsCredentialSummary(
            name: "Ads",
            clientId: "client",
            teamId: "team",
            keyId: "key",
            adAccountId: "1"
        )
        await configured.submitSelectedVersionForReview(releaseType: .afterApproval)
        #expect(configured.offerPromoteAfterSubmit)
    }
}

private func decodeJSONPart(_ value: String) throws -> [String: Any] {
    var base64 = value
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 {
        base64.append("=")
    }
    let data = try #require(Data(base64Encoded: base64))
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
