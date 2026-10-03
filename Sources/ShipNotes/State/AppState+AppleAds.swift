import Foundation

enum AppleAdsLoadResult: Sendable {
    case success(AppleAdsCredentials?)
    case failure(AppleAdsCredentialError)
}

@MainActor
extension AppState {
    var isAppleAdsConfigured: Bool {
        !isUsingSampleAds && appleAdsService != nil && appleAdsCredentialSummary != nil
    }

    var selectedAppleAdsCampaign: AppleAdsCampaign? {
        guard let id = selectedAppleAdsCampaignId else { return nil }
        return appleAdsCampaigns.first { $0.id == id }
    }

    var selectedAppleAdsAdGroup: AppleAdsAdGroup? {
        guard let id = selectedAppleAdsAdGroupId else { return nil }
        return appleAdsAdGroups.first { $0.id == id }
    }

    var appleAdsKeywordSeeds: [String] {
        AppleAdsKeywordSeed.phrases(
            keywords: selectedStoreCopy?.localMetadata.keywords ?? "",
            whatsNew: selectedLocaleNote?.localText ?? localeNotes.first?.localText ?? "",
            appName: selectedApp?.name
        )
    }

    var selectedAppleAdsMetrics: AppleAdsCampaignMetrics? {
        guard let id = selectedAppleAdsCampaignId else { return nil }
        return appleAdsMetricsByCampaign[id]
    }

    func saveAppleAdsCredentials(
        name: String,
        clientId: String,
        teamId: String,
        keyId: String,
        privateKeyPEM: String,
        adAccountId: String?
    ) async {
        isLoadingAds = true
        defer { isLoadingAds = false }
        do {
            let existing = try appleAdsCredentialStore.load()?.privateKeyPEM ?? ""
            let trimmedKey = privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
            let credentials = try AppleAdsCredentials(
                name: name,
                clientId: clientId,
                teamId: teamId,
                keyId: keyId,
                privateKeyPEM: trimmedKey.isEmpty ? existing : privateKeyPEM,
                adAccountId: adAccountId ?? appleAdsCredentialSummary?.adAccountId
            ).validated()
            try appleAdsCredentialStore.save(credentials)
            appleAdsCredentialSummary = credentials.summary
            await connectAppleAds(credentials: credentials)
        } catch {
            handleError(error)
        }
    }

    func testAppleAdsConnection() async {
        isLoadingAds = true
        defer { isLoadingAds = false }
        do {
            guard let credentials = try appleAdsCredentialStore.load() else {
                throw AppleAdsCredentialError.missingPrivateKey
            }
            await connectAppleAds(credentials: credentials)
        } catch {
            handleError(error)
        }
    }

    func removeAppleAdsCredentials() {
        do {
            try appleAdsCredentialStore.delete()
            installSampleAppleAds()
            lastError = nil
        } catch {
            handleError(error)
        }
    }

    func selectAppleAdsAccount(_ id: String) async {
        do {
            guard var credentials = try appleAdsCredentialStore.load() else {
                throw AppleAdsCredentialError.missingPrivateKey
            }
            credentials.adAccountId = id
            try appleAdsCredentialStore.save(credentials)
            appleAdsCredentialSummary = credentials.summary
            await connectAppleAds(credentials: credentials)
        } catch {
            handleError(error)
        }
    }

    func refreshAppleAds() {
        Task { await refreshAppleAdsForSelectedApp() }
    }

    func selectAppleAdsCampaign(_ id: String) {
        selectedAppleAdsCampaignId = id
        Task { await refreshAppleAdsCampaignDetails() }
    }

    func selectAppleAdsAdGroup(_ id: String) {
        selectedAppleAdsAdGroupId = id
        Task { await refreshAppleAdsKeywords() }
    }

    func suggestAppleAdsKeywords() {
        Task { await loadAppleAdsKeywordSuggestions() }
    }

    func applyAppleAdsKeywordSuggestions() {
        Task { await applySelectedAppleAdsKeywordSuggestions() }
    }

    func setAppleAdsCampaignEnabled(_ campaign: AppleAdsCampaign, enabled: Bool) {
        pendingAppleAdsStatusChange = PendingAppleAdsStatusChange(
            campaignId: campaign.id,
            status: enabled ? "ENABLED" : "PAUSED"
        )
    }

    func confirmAppleAdsStatusChange() {
        guard let pending = pendingAppleAdsStatusChange else { return }
        pendingAppleAdsStatusChange = nil
        Task { await updateAppleAdsCampaignStatus(id: pending.campaignId, status: pending.status) }
    }

    func cancelAppleAdsStatusChange() {
        pendingAppleAdsStatusChange = nil
    }

    func presentPromoteVersionSheet() {
        showPromoteVersionSheet = true
    }

    /// Returns whether the campaign was created.
    @discardableResult
    func promoteSelectedVersion(_ request: AppleAdsPromoteRequest) async -> Bool {
        guard let service = appleAdsService else {
            setError(L("Connect Apple Ads in Settings before creating a campaign."), category: .auth)
            return false
        }
        isLoadingAds = true
        defer { isLoadingAds = false }
        do {
            let eligibility = try await service.checkAppEligibility(
                adamId: request.adamId, countries: request.countries)
            guard eligibility.isEligible else {
                setError(
                    eligibility.reasons.first ?? L("This app is not eligible for Apple Ads."),
                    category: .validation
                )
                return false
            }
            let created = try await service.createSearchResultsCampaign(request)
            showPromoteVersionSheet = false
            await refreshAppleAdsForSelectedApp()
            selectedAppleAdsCampaignId = created.id
            lastError = nil
            return true
        } catch {
            handleError(error)
            return false
        }
    }

    func bootstrapAppleAdsFromKeychainInBackground() async {
        let store = appleAdsCredentialStore
        let loadResult = await Task.detached(priority: .userInitiated) { () -> AppleAdsLoadResult in
            do {
                return .success(try store.load())
            } catch let error as AppleAdsCredentialError {
                return .failure(error)
            } catch {
                return .failure(.invalidStoredData)
            }
        }.value

        switch loadResult {
        case .success(let credentials):
            if let credentials {
                await connectAppleAds(credentials: credentials)
            } else {
                installSampleAppleAds()
            }
        case .failure(let error):
            installSampleAppleAds()
            handleError(error)
        }
    }

    func resetAppleAdsSelection() {
        adsRefreshID = UUID()
        adsDetailsID = UUID()
        adsKeywordsID = UUID()
        appleAdsCampaigns = []
        appleAdsMetricsByCampaign = [:]
        selectedAppleAdsCampaignId = nil
        appleAdsAdGroups = []
        selectedAppleAdsAdGroupId = nil
        appleAdsKeywords = []
        appleAdsSearchTerms = []
        appleAdsSuggestions = []
        appleAdsSelectedSuggestionTexts = []
        pendingAppleAdsStatusChange = nil
        showAppleAdsKeywordConfirm = false
        offerPromoteAfterSubmit = false
    }

    func installSampleAppleAds() {
        resetAppleAdsSelection()
        appleAdsService = SampleAppleAdsService()
        isUsingSampleAds = true
        appleAdsCredentialSummary = nil
        appleAdsAccounts = []
        appleAdsConnectionStatus = "Using sample Apple Ads data"
        selectedAppleAdsAccountId = "sample-ads-1"
        appleAdsAccountCapabilities = AppleAdsAccount(
            id: "sample-ads-1",
            name: "Sample Ads Account",
            orgId: "sample-org",
            currency: "USD",
            timeZone: "UTC",
            productFeatures: ["APPSTORE_APP_MANUAL"],
            hasContentProviderDelegation: true
        )
        Task { await refreshAppleAdsForSelectedApp() }
    }

    func connectAppleAds(credentials: AppleAdsCredentials) async {
        resetAppleAdsSelection()
        lastError = nil
        do {
            let bootstrapClient = AppleAdsBootstrapClient(credentials: credentials)
            let acls = try await bootstrapClient.fetchACLs()
            appleAdsAccounts = acls.map(\.account)
            var resolved = credentials
            if resolved.adAccountId == nil || !(appleAdsAccounts.contains { $0.id == resolved.adAccountId }) {
                resolved.adAccountId = appleAdsAccounts.first?.id
            }
            if resolved.adAccountId != credentials.adAccountId {
                try? appleAdsCredentialStore.save(resolved)
            }
            appleAdsCredentialSummary = resolved.summary
            guard let accountId = resolved.adAccountId else {
                appleAdsService = nil
                isUsingSampleAds = false
                appleAdsConnectionStatus = "Connected to Apple Ads"
                selectedAppleAdsAccountId = nil
                appleAdsAccountCapabilities = nil
                appleAdsCampaigns = []
                appleAdsMetricsByCampaign = [:]
                return
            }
            let client = try AppleAdsClient(credentials: resolved)
            appleAdsService = client
            isUsingSampleAds = false
            appleAdsCredentialSummary = resolved.summary
            selectedAppleAdsAccountId = accountId
            appleAdsConnectionStatus = "Connected to Apple Ads"
            if let account = try? await client.fetchAdAccount(id: accountId) {
                appleAdsAccountCapabilities = account
            } else {
                appleAdsAccountCapabilities = appleAdsAccounts.first { $0.id == accountId }
            }
            await refreshAppleAdsForSelectedApp()
        } catch {
            installSampleAppleAds()
            handleError(error)
        }
    }

    func refreshAppleAdsForSelectedApp() async {
        let requestID = UUID()
        adsRefreshID = requestID
        let accountID = selectedAppleAdsAccountId
        guard let service = appleAdsService, let adamId = selectedAppId else {
            appleAdsCampaigns = []
            appleAdsMetricsByCampaign = [:]
            selectedAppleAdsCampaignId = nil
            return
        }
        isLoadingAds = true
        defer { isLoadingAds = false }
        do {
            let campaigns = try await service.queryCampaigns(adamId: adamId)
            guard !Task.isCancelled, adsRefreshID == requestID, selectedAppId == adamId,
                selectedAppleAdsAccountId == accountID
            else { return }
            appleAdsCampaigns = campaigns
            // Metrics don't depend on the selected campaign's details; fetch
            // them while the details load instead of afterwards. An
            // unstructured task, not `async let`: async-let children join an
            // implicit TaskGroup whose mid-flight teardown crashed in
            // TaskGroup::offer on the macOS 27.2 beta runtime.
            let dates = reportDateRange(appleAdsReportRange)
            let reportTask = Task {
                try await service.queryCampaignReports(
                    campaignIds: campaigns.map(\.id),
                    start: dates.start,
                    end: dates.end
                )
            }
            if let selected = selectedAppleAdsCampaignId, campaigns.contains(where: { $0.id == selected }) {
                await refreshAppleAdsCampaignDetails()
            } else {
                selectedAppleAdsCampaignId = campaigns.first?.id
                if selectedAppleAdsCampaignId != nil {
                    await refreshAppleAdsCampaignDetails()
                } else {
                    appleAdsAdGroups = []
                    appleAdsKeywords = []
                    appleAdsSearchTerms = []
                }
            }
            let metrics = try await reportTask.value
            guard !Task.isCancelled, adsRefreshID == requestID, selectedAppId == adamId,
                selectedAppleAdsAccountId == accountID
            else { return }
            let budgetCurrencies = Dictionary(
                campaigns.compactMap { campaign in campaign.dailyBudgetCurrency.map { (campaign.id, $0) } },
                uniquingKeysWith: { first, _ in first }
            )
            appleAdsMetricsByCampaign = Dictionary(
                metrics.map { metric -> (String, AppleAdsCampaignMetrics) in
                    var metric = metric
                    // Reports omit the currency when there was no spend.
                    if metric.currency.isEmpty, let currency = budgetCurrencies[metric.campaignId] {
                        metric.currency = currency
                    }
                    return (metric.campaignId, metric)
                },
                uniquingKeysWith: { _, new in new }
            )
        } catch {
            guard !Task.isCancelled, adsRefreshID == requestID, selectedAppId == adamId,
                selectedAppleAdsAccountId == accountID
            else { return }
            handleError(error)
        }
    }

    func refreshAppleAdsCampaignDetails() async {
        guard let service = appleAdsService, let campaignId = selectedAppleAdsCampaignId else { return }
        let requestID = UUID()
        adsDetailsID = requestID
        let appID = selectedAppId
        let accountID = selectedAppleAdsAccountId
        do {
            let groups = try await service.queryAdGroups(campaignId: campaignId)
            guard !Task.isCancelled, adsDetailsID == requestID, selectedAppleAdsCampaignId == campaignId,
                selectedAppId == appID, selectedAppleAdsAccountId == accountID
            else { return }
            appleAdsAdGroups = groups
            if let selected = selectedAppleAdsAdGroupId, groups.contains(where: { $0.id == selected }) {
                await refreshAppleAdsKeywords()
            } else {
                selectedAppleAdsAdGroupId = groups.first?.id
                await refreshAppleAdsKeywords()
            }
            let dates = reportDateRange(appleAdsReportRange)
            let terms = try await service.querySearchTerms(
                campaignId: campaignId,
                start: dates.start,
                end: dates.end
            )
            guard !Task.isCancelled, adsDetailsID == requestID, selectedAppleAdsCampaignId == campaignId,
                selectedAppId == appID, selectedAppleAdsAccountId == accountID
            else { return }
            appleAdsSearchTerms = terms
        } catch {
            guard !Task.isCancelled, adsDetailsID == requestID, selectedAppleAdsCampaignId == campaignId,
                selectedAppId == appID, selectedAppleAdsAccountId == accountID
            else { return }
            handleError(error)
        }
    }

    func refreshAppleAdsKeywords() async {
        let requestID = UUID()
        adsKeywordsID = requestID
        let campaignID = selectedAppleAdsCampaignId
        let accountID = selectedAppleAdsAccountId
        let appID = selectedAppId
        guard let service = appleAdsService, let adGroupId = selectedAppleAdsAdGroupId else {
            appleAdsKeywords = []
            return
        }
        do {
            let keywords = try await service.queryKeywords(adGroupId: adGroupId)
            guard !Task.isCancelled, adsKeywordsID == requestID, selectedAppleAdsAdGroupId == adGroupId,
                selectedAppleAdsCampaignId == campaignID, selectedAppleAdsAccountId == accountID, selectedAppId == appID
            else { return }
            appleAdsKeywords = keywords
        } catch {
            guard !Task.isCancelled, adsKeywordsID == requestID, selectedAppleAdsAdGroupId == adGroupId,
                selectedAppleAdsCampaignId == campaignID, selectedAppleAdsAccountId == accountID, selectedAppId == appID
            else { return }
            handleError(error)
        }
    }

    func loadAppleAdsKeywordSuggestions() async {
        guard let service = appleAdsService, let adamId = selectedAppId else { return }
        let accountID = selectedAppleAdsAccountId
        let requestID = adsRefreshID
        isLoadingAds = true
        defer { isLoadingAds = false }
        do {
            let suggestions = try await service.queryKeywordSuggestions(
                adamId: adamId,
                seeds: appleAdsKeywordSeeds
            )
            guard selectedAppId == adamId, selectedAppleAdsAccountId == accountID, adsRefreshID == requestID else {
                return
            }
            appleAdsSuggestions = suggestions
            appleAdsSelectedSuggestionTexts = Set(suggestions.map(\.text))
        } catch {
            handleError(error)
        }
    }

    func applySelectedAppleAdsKeywordSuggestions() async {
        guard let service = appleAdsService, let adGroupId = selectedAppleAdsAdGroupId else {
            setError(L("Select an ad group before applying keywords."), category: .validation)
            return
        }
        let drafts =
            appleAdsSuggestions
            .filter { appleAdsSelectedSuggestionTexts.contains($0.text) }
            .map { AppleAdsKeywordDraft(text: $0.text, matchType: "BROAD", bidAmount: nil) }
        guard !drafts.isEmpty else { return }
        isLoadingAds = true
        defer { isLoadingAds = false }
        do {
            _ = try await service.bulkCreateKeywords(adGroupId: adGroupId, keywords: drafts)
            showAppleAdsKeywordConfirm = false
            await refreshAppleAdsKeywords()
            lastError = nil
        } catch {
            handleError(error)
        }
    }

    func updateAppleAdsCampaignStatus(id: String, status: String) async {
        guard let service = appleAdsService else { return }
        isLoadingAds = true
        defer { isLoadingAds = false }
        do {
            let updated = try await service.updateCampaignStatus(id: id, status: status)
            if let index = appleAdsCampaigns.firstIndex(where: { $0.id == id }) {
                appleAdsCampaigns[index] = updated
            }
            lastError = nil
        } catch {
            handleError(error)
        }
    }

    func reportDateRange(_ range: AppleAdsReportRange) -> (start: String, end: String) {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(range.dayCount - 1), to: end) ?? end
        return (AppleAdsDateFormat.day(start), AppleAdsDateFormat.day(end))
    }
}

/// Temporary client used only to list ACLs before an ad account is chosen.
/// ACL calls are unscoped, so they do not need `X-AP-Context`.
private struct AppleAdsBootstrapClient {
    let credentials: AppleAdsCredentials

    func fetchACLs() async throws -> [AppleAdsACL] {
        let provider = AppleAdsTokenProvider(credentials: credentials)
        let session = AppStoreConnectClient.defaultSession
        let token = try await provider.accessToken()
        var request = URLRequest(url: URL(string: "https://api.ads.apple.com/v1/acls")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AppleAdsClientError.requestFailed(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: message
            )
        }
        let envelope = try JSONDecoder().decode(AppleAdsEnvelope<AppleAdsListResult<AdsACLDTO>>.self, from: data)
        return (envelope.result?.extracted ?? []).map(\.asModel)
    }
}
