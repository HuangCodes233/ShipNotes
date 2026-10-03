import SwiftUI

struct AppleAdsSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var adsName = ""
    @State private var adsClientId = ""
    @State private var adsTeamId = ""
    @State private var adsKeyId = ""
    @State private var adsPrivateKeyPEM = ""

    // Hydrate once so switching tabs preserves unsaved form values.
    @State private var hasLoadedSummary = false

    @ViewBuilder
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L("Apple Ads"), systemImage: state.isUsingSampleAds ? "key.slash" : "key.fill")
                        .font(.headline)
                    Spacer()
                    if state.isLoadingAds {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(L(state.appleAdsConnectionStatus))
                    .font(.callout)
                    .foregroundStyle(state.isUsingSampleAds ? Color.secondary : Color.green)

                Text(
                    L(
                        "Apple Ads uses a different key from App Store Connect. Generate an EC P-256 key, upload the public key in Apple Ads → Account Settings → API, then paste Client ID, Team ID, Key ID, and the private key here."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text(L("Name"))
                            .foregroundStyle(.secondary)
                        TextField("Apple Ads", text: $adsName)
                    }
                    GridRow {
                        Text(L("Client ID"))
                            .foregroundStyle(.secondary)
                        TextField("SEARCHADS.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $adsClientId)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text(L("Team ID"))
                            .foregroundStyle(.secondary)
                        TextField("SEARCHADS.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $adsTeamId)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text(L("Key ID"))
                            .foregroundStyle(.secondary)
                        TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $adsKeyId)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L("Private Key"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            importPrivateKey()
                        } label: {
                            Label(L("Import .pem"), systemImage: "square.and.arrow.down")
                        }
                        .controlSize(.small)
                    }

                    TextEditor(text: $adsPrivateKeyPEM)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 72)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.separator, lineWidth: 0.5)
                        )

                    if state.appleAdsCredentialSummary != nil
                        && adsPrivateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        Text(L("Private key is stored in Keychain. Leave this empty to keep the current key."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !state.appleAdsAccounts.isEmpty {
                    Picker(
                        L("Ad Account"),
                        selection: Binding(
                            get: { state.selectedAppleAdsAccountId ?? "" },
                            set: { id in
                                guard !id.isEmpty else { return }
                                Task { await state.selectAppleAdsAccount(id) }
                            }
                        )
                    ) {
                        ForEach(state.appleAdsAccounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    .labelsHidden()
                }

                if let account = state.appleAdsAccountCapabilities {
                    Text(
                        account.canRunAppStoreCampaigns && account.hasContentProviderDelegation
                            ? L("This ad account can run App Store campaigns.")
                            : L(
                                "Check APPSTORE_APP_MANUAL and CONTENT_PROVIDER on this ad account before creating campaigns."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Button(role: .destructive) {
                        state.removeAppleAdsCredentials()
                        clearAdsForm()
                    } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }
                    .disabled(state.appleAdsCredentialSummary == nil || state.isLoadingAds)

                    Spacer()

                    Button {
                        Task { await state.testAppleAdsConnection() }
                    } label: {
                        Label(L("Test"), systemImage: "network")
                    }
                    .disabled(state.appleAdsCredentialSummary == nil || state.isLoadingAds)

                    Button {
                        Task {
                            await state.saveAppleAdsCredentials(
                                name: adsName,
                                clientId: adsClientId,
                                teamId: adsTeamId,
                                keyId: adsKeyId,
                                privateKeyPEM: adsPrivateKeyPEM,
                                adAccountId: state.selectedAppleAdsAccountId
                            )
                            adsPrivateKeyPEM = ""
                            loadSummary()
                        }
                    } label: {
                        Label(L("Save & Connect"), systemImage: "checkmark.circle")
                    }
                    .primarySyncButton()
                    .disabled(
                        adsClientId.isEmpty
                            || adsTeamId.isEmpty
                            || adsKeyId.isEmpty
                            || (state.appleAdsCredentialSummary == nil
                                && adsPrivateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            || state.isLoadingAds
                    )
                }
            }
        }
        .onAppear(perform: loadSummaryIfNeeded)
    }

    private func loadSummaryIfNeeded() {
        guard !hasLoadedSummary else { return }
        hasLoadedSummary = true
        loadSummary()
    }

    private func loadSummary() {
        guard let summary = state.appleAdsCredentialSummary else { return }
        adsName = summary.name
        adsClientId = summary.clientId
        adsTeamId = summary.teamId
        adsKeyId = summary.keyId
    }
    private func clearAdsForm() {
        adsName = ""
        adsClientId = ""
        adsTeamId = ""
        adsKeyId = ""
        adsPrivateKeyPEM = ""
    }

    private func importPrivateKey() {
        PrivateKeyImporter.present { result in
            switch result {
            case .success(let key): adsPrivateKeyPEM = key
            case .failure(let error): state.handleError(error)
            }
        }
    }
}
