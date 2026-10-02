import SwiftUI

struct PromoteVersionSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var campaignName = ""
    @State private var dailyBudget = "20.00"
    @State private var defaultBid = "1.00"
    @State private var selectedCountries: Set<String> = ["US"]
    @State private var selectedKeywords: Set<String> = []
    @State private var storefronts: [String] = ["US", "JP", "CN", "GB"]
    @State private var currency = "USD"
    @State private var localError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                form
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 560)
        .task { await loadDefaults() }
    }

    private var header: some View {
        HStack {
            Label(L("Promote this version"), systemImage: "megaphone.fill")
                .font(.headline)
            Spacer()
            if state.isLoadingAds {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Creates a paused Search results campaign. Enable it after reviewing its setup."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state.isUsingSampleAds {
                Text(L("Sample data only — nothing is billed."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            labeled(L("Campaign name")) {
                TextField(L("Campaign name"), text: $campaignName)
                    .textFieldStyle(.roundedBorder)
            }
            labeled(L("Daily budget")) {
                HStack {
                    TextField("20.00", text: $dailyBudget)
                        .textFieldStyle(.roundedBorder)
                    Text(currency).foregroundStyle(.secondary)
                }
            }
            labeled(L("Default bid")) {
                HStack {
                    TextField("1.00", text: $defaultBid)
                        .textFieldStyle(.roundedBorder)
                    Text(currency).foregroundStyle(.secondary)
                }
            }

            Text(L("Countries")).font(.headline)
            FlexibleCountryList(storefronts: storefronts, selected: $selectedCountries)

            Text(L("Keywords from store copy")).font(.headline)
            if selectedKeywords.isEmpty && state.appleAdsKeywordSeeds.isEmpty {
                Text(L("No keywords found in store copy or What’s New."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.appleAdsKeywordSeeds, id: \.self) { phrase in
                    Toggle(phrase, isOn: Binding(
                        get: { selectedKeywords.contains(phrase) },
                        set: { on in
                            if on { selectedKeywords.insert(phrase) } else { selectedKeywords.remove(phrase) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }

            if let localError {
                Text(localError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            content()
        }
    }

    private var footer: some View {
        HStack {
            Button(L("Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                submit()
            } label: {
                Label(L("Create campaign"), systemImage: "plus.circle.fill")
            }
            .keyboardShortcut(.defaultAction)
            .primarySyncButton()
            .disabled(!canSubmit || state.isLoadingAds)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var canSubmit: Bool {
        !campaignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && AppleAdsPromoteRequest.validAmounts(budget: dailyBudget, bid: defaultBid)
            && !selectedCountries.isEmpty
            && state.selectedAppId != nil
    }

    private func loadDefaults() async {
        let appName = state.selectedApp?.name ?? "App"
        let version = state.selectedVersion?.versionString ?? ""
        if campaignName.isEmpty {
            campaignName = version.isEmpty ? appName : "\(appName) \(version) — Search"
        }
        selectedKeywords = Set(state.appleAdsKeywordSeeds)
        if let service = state.appleAdsService, let adamId = state.selectedAppId {
            if let details = try? await service.fetchAppDetails(adamId: adamId) {
                if !details.availableStorefronts.isEmpty {
                    storefronts = details.availableStorefronts
                    selectedCountries = Set(details.availableStorefronts.prefix(3))
                }
                if let detailsCurrency = details.currency, !detailsCurrency.isEmpty {
                    currency = detailsCurrency
                }
            }
        }
        if let accountCurrency = state.appleAdsAccountCapabilities?.currency {
            currency = accountCurrency
        }
    }

    private func submit() {
        guard canSubmit else { return }
        guard let adamId = state.selectedAppId else { return }
        localError = nil
        let request = AppleAdsPromoteRequest(
            adamId: adamId,
            name: campaignName.trimmingCharacters(in: .whitespacesAndNewlines),
            dailyBudget: dailyBudget,
            currency: currency,
            countries: selectedCountries.sorted(),
            defaultBid: defaultBid,
            keywords: selectedKeywords.sorted().map {
                AppleAdsKeywordDraft(text: $0, matchType: "BROAD", bidAmount: nil)
            }
        )
        Task {
            let promoted = await state.promoteSelectedVersion(request)
            if !promoted {
                localError = state.lastError?.message ?? L("The campaign was not created.")
            }
        }
    }
}

private struct FlexibleCountryList: View {
    let storefronts: [String]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(storefronts, id: \.self) { code in
                Toggle(code, isOn: Binding(
                    get: { selected.contains(code) },
                    set: { on in
                        if on { selected.insert(code) } else { selected.remove(code) }
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }
}
