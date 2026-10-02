import SwiftUI

struct AdsWorkspaceView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.selectedAppId == nil {
            SelectAppEmptyState(description: L("Choose an app from the sidebar to view its Apple Ads campaigns."))
        } else {
            mainWorkspace
        }
    }

    private var mainWorkspace: some View {
        HSplitView {
            campaignList
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 480)
            detailPane
                .frame(minWidth: 420, maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: state.selectedAppId) {
            await state.refreshAppleAdsForSelectedApp()
        }
        .onChange(of: state.appleAdsReportRange) { _, _ in
            state.refreshAppleAds()
        }
        .confirmationDialog(
            L("Apply keywords to the selected ad group?"),
            isPresented: Binding(
                get: { state.showAppleAdsKeywordConfirm },
                set: { state.showAppleAdsKeywordConfirm = $0 }
            )
        ) {
            Button(L("Apply Keywords")) {
                state.applyAppleAdsKeywordSuggestions()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("%d keyword(s) will be created on the selected ad group.", state.appleAdsSelectedSuggestionTexts.count))
        }
        .confirmationDialog(
            statusDialogTitle,
            isPresented: Binding(
                get: { state.pendingAppleAdsStatusChange != nil },
                set: { if !$0 { state.cancelAppleAdsStatusChange() } }
            )
        ) {
            if statusDialogIsPause {
                Button(statusDialogConfirm, role: .destructive) {
                    state.confirmAppleAdsStatusChange()
                }
            } else {
                Button(statusDialogConfirm) {
                    state.confirmAppleAdsStatusChange()
                }
            }
            Button(L("Cancel"), role: .cancel) {
                state.cancelAppleAdsStatusChange()
            }
        } message: {
            Text(state.isUsingSampleAds
                 ? L("Sample data only — nothing is billed.")
                 : L("This changes a live Apple Ads campaign."))
        }
    }

    private var campaignList: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            capabilitiesBanner
            if state.appleAdsCampaigns.isEmpty {
                emptyCampaigns
            } else {
                List(state.appleAdsCampaigns, selection: Binding(
                    get: { state.selectedAppleAdsCampaignId },
                    set: { if let id = $0 { state.selectAppleAdsCampaign(id) } }
                )) { campaign in
                    campaignRow(campaign)
                        .tag(campaign.id)
                }
                .listStyle(.inset)
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Apple Ads"))
                    .font(.title2.weight(.semibold))
                if state.isLoadingAds {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button {
                    state.presentPromoteVersionSheet()
                } label: {
                    Label(L("Promote…"), systemImage: "megaphone")
                }
                .disabled(state.selectedAppId == nil)
            }
            Text(L(state.appleAdsConnectionStatus))
                .font(.callout)
                .foregroundStyle(state.isUsingSampleAds ? Color.secondary : Color.green)
            Picker(L("Range"), selection: Binding(
                get: { state.appleAdsReportRange },
                set: { state.appleAdsReportRange = $0 }
            )) {
                ForEach(AppleAdsReportRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
        }
    }

    @ViewBuilder
    private var capabilitiesBanner: some View {
        if let account = state.appleAdsAccountCapabilities {
            HStack(spacing: 8) {
                Image(systemName: account.canRunAppStoreCampaigns && account.hasContentProviderDelegation
                      ? "checkmark.seal"
                      : "exclamationmark.triangle")
                    .foregroundStyle(account.canRunAppStoreCampaigns && account.hasContentProviderDelegation ? .green : .orange)
                Text(capabilityCopy(account))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func capabilityCopy(_ account: AppleAdsAccount) -> String {
        if account.canRunAppStoreCampaigns && account.hasContentProviderDelegation {
            return L("This ad account can run App Store campaigns.")
        }
        if !account.canRunAppStoreCampaigns {
            return L("This ad account is missing APPSTORE_APP_MANUAL. App Store campaigns cannot go live.")
        }
        return L("This ad account is missing a CONTENT_PROVIDER delegation.")
    }

    @ViewBuilder
    private var emptyCampaigns: some View {
        if state.isUsingSampleAds && state.appleAdsCredentialSummary == nil {
            ContentUnavailableView {
                Label(L("Connect Apple Ads"), systemImage: "key")
            } description: {
                Text(L("Add an Apple Ads API key in Settings to load live campaigns. Sample campaigns are shown for apps that have them."))
            }
        } else if state.appleAdsAccounts.isEmpty && !state.isUsingSampleAds {
            ContentUnavailableView {
                Label(L("No Apple Ads account"), systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text(L("This API key has no ad account. Create one in Apple Ads, then test the connection again."))
            }
        } else {
            ContentUnavailableView {
                Label(L("No campaigns for this app"), systemImage: "megaphone")
            } description: {
                Text(L("This App Store ID has no Apple Ads campaigns yet. Use Promote to create a Search results campaign."))
            }
        }
    }

    private func campaignRow(_ campaign: AppleAdsCampaign) -> some View {
        let metrics = state.appleAdsMetricsByCampaign[campaign.id]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(campaign.name)
                    .font(.headline)
                Spacer()
                Text(campaign.displayStatus ?? campaign.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let metrics {
                Text(L("Spend %1$@ · %2$d taps · %3$d installs", currency(metrics.spend, metrics.currency), metrics.taps, metrics.installs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var detailPane: some View {
        // An ad group can have up to 200 keywords plus 50 search terms; without
        // scrolling the pane clipped them and pushed "Apply to ad group" out of
        // reach.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let campaign = state.selectedAppleAdsCampaign {
                    campaignDetail(campaign)
                } else {
                    Text(L("Select a campaign to see reports and keywords."))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func campaignDetail(_ campaign: AppleAdsCampaign) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(campaign.name).font(.title3.weight(.semibold))
                if let budget = campaign.dailyBudgetAmount {
                    Text(L("Daily budget: %@ %@", budget, campaign.dailyBudgetCurrency ?? ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                state.setAppleAdsCampaignEnabled(campaign, enabled: !campaign.isEnabled)
            } label: {
                Label(
                    campaign.isEnabled ? L("Pause") : L("Enable"),
                    systemImage: campaign.isEnabled ? "pause.circle" : "play.circle"
                )
            }
        }

        if let metrics = state.appleAdsMetricsByCampaign[campaign.id] {
            metricsGrid(metrics)
        }

        adGroupSection
        keywordSection
        searchTermSection
        suggestionSection
    }

    private func metricsGrid(_ metrics: AppleAdsCampaignMetrics) -> some View {
        HStack(spacing: 16) {
            metricTile(L("Spend"), currency(metrics.spend, metrics.currency))
            metricTile(L("Taps"), "\(metrics.taps)")
            metricTile(L("Installs"), "\(metrics.installs)")
            metricTile(L("CPA"), metrics.cpa.map { currency($0, metrics.currency) } ?? "—")
        }
    }

    private func metricTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var adGroupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Ad Groups")).font(.headline)
            Picker(L("Ad Group"), selection: Binding(
                get: { state.selectedAppleAdsAdGroupId ?? "" },
                set: { if !$0.isEmpty { state.selectAppleAdsAdGroup($0) } }
            )) {
                ForEach(state.appleAdsAdGroups) { group in
                    Text(group.name).tag(group.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320)
        }
    }

    private var keywordSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Keywords")).font(.headline)
            if state.appleAdsKeywords.isEmpty {
                Text(L("No targeting keywords on this ad group."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.appleAdsKeywords) { keyword in
                    HStack {
                        Text(keyword.text)
                        Spacer()
                        Text(keyword.matchType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var searchTermSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Search terms")).font(.headline)
            if state.appleAdsSearchTerms.isEmpty {
                Text(L("No search terms in this range."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.appleAdsSearchTerms) { term in
                    HStack {
                        Text(term.text)
                        Spacer()
                        Text(L("%d taps", term.taps))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Keyword ideas from store copy")).font(.headline)
                Spacer()
                Button(L("Suggest from copy")) {
                    state.suggestAppleAdsKeywords()
                }
                .disabled(state.selectedAppId == nil || state.isLoadingAds)
            }
            if state.appleAdsSuggestions.isEmpty {
                Text(L("Pull suggestions from What’s New and App Store keywords, then apply them to the selected ad group."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(state.appleAdsSuggestions) { suggestion in
                    Toggle(isOn: Binding(
                        get: { state.appleAdsSelectedSuggestionTexts.contains(suggestion.text) },
                        set: { selected in
                            if selected {
                                state.appleAdsSelectedSuggestionTexts.insert(suggestion.text)
                            } else {
                                state.appleAdsSelectedSuggestionTexts.remove(suggestion.text)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.text)
                            Text(suggestion.source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                Button {
                    state.showAppleAdsKeywordConfirm = true
                } label: {
                    Label(L("Apply to ad group"), systemImage: "plus.circle")
                }
                .disabled(state.selectedAppleAdsAdGroupId == nil || state.appleAdsSelectedSuggestionTexts.isEmpty)
                .primarySyncButton()
            }
        }
    }

    private var statusDialogTitle: String {
        state.pendingAppleAdsStatusChange?.status == "PAUSED"
            ? L("Pause this campaign?")
            : L("Enable this campaign?")
    }

    private var statusDialogConfirm: String {
        state.pendingAppleAdsStatusChange?.status == "PAUSED" ? L("Pause") : L("Enable")
    }

    private var statusDialogIsPause: Bool {
        state.pendingAppleAdsStatusChange?.status == "PAUSED"
    }

    private func currency(_ amount: Double, _ code: String) -> String {
        // Without a currency code a currency style would silently use the
        // Mac's locale currency; show the plain amount instead.
        guard !code.isEmpty else {
            return amount.formatted(.number.precision(.fractionLength(2)))
        }
        return amount.formatted(.currency(code: code))
    }
}
