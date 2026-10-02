import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var accountName = ""
    @State private var issuerId = ""
    @State private var keyId = ""
    @State private var privateKeyPEM = ""
    @State private var aiProvider: AIProvider = .anthropic
    @State private var aiApiKey: String = ""
    @State private var aiBaseURL: String = ""
    @State private var aiModel: String = ""
    @State private var aiSaveFeedback: AISaveFeedback?
    @State private var visionAIProvider: AIProvider = .openai
    @State private var visionAIApiKey: String = ""
    @State private var visionAIBaseURL: String = ""
    @State private var visionAIModel: String = ""
    @State private var visionAISaveFeedback: AISaveFeedback?
    @State private var adsName = ""
    @State private var adsClientId = ""
    @State private var adsTeamId = ""
    @State private var adsKeyId = ""
    @State private var adsPrivateKeyPEM = ""

    // Persisted UI preferences. @AppStorage MUST live as a stored property on
    // the View struct — declaring it inside a @ViewBuilder body silently
    // breaks the binding (writes succeed but the view never re-renders, so
    // the checkbox looks unclickable).
    @AppStorage(SettingsKey.stripMarkdownOnSync) private var stripMarkdown: Bool = false
    @AppStorage(LanguageManager.appStorageKey) private var uiLanguage: String = ""
    @AppStorage(AppearanceManager.appStorageKey) private var appearance: String = ""

    var body: some View {
        TabView {
            accountTab
                .tabItem { Label(L("Account"), systemImage: "key") }
            adsTab
                .tabItem { Label(L("Apple Ads"), systemImage: "megaphone") }
            generalTab
                .tabItem { Label(L("General"), systemImage: "gear") }
            aiTab
                .tabItem { Label(L("AI"), systemImage: "sparkles") }
        }
        .frame(width: 580, height: 540)
        .padding()
        .preferredColorScheme((AppearanceOption(rawValue: appearance) ?? .system).colorScheme)
        .onAppear(perform: loadSummary)
    }

    @ViewBuilder
    private var accountTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("App Store Connect"), systemImage: state.isUsingMockData ? "key.slash" : "key.fill")
                    .font(.headline)
                Spacer()
                if state.isLoadingRemote {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(L(state.connectionStatus))
                .font(.callout)
                .foregroundStyle(state.isUsingMockData ? Color.secondary : Color.green)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L("Name"))
                        .foregroundStyle(.secondary)
                    TextField("App Store Connect", text: $accountName)
                }
                GridRow {
                    Text(L("Issuer ID"))
                        .foregroundStyle(.secondary)
                    TextField("00000000-0000-0000-0000-000000000000", text: $issuerId)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(L("Key ID"))
                        .foregroundStyle(.secondary)
                    TextField("ABCD1234EF", text: $keyId)
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
                        Label(L("Import .p8"), systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.small)
                }

                TextEditor(text: $privateKeyPEM)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 96)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )

                if state.credentialSummary != nil && privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L("Private key is stored in Keychain. Leave this empty to keep the current key."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(role: .destructive) {
                    state.removeCredentials()
                    clearForm()
                } label: {
                    Label(L("Remove"), systemImage: "trash")
                }
                .disabled(state.credentialSummary == nil || state.isLoadingRemote)

                Spacer()

                Button {
                    Task { await state.testConnection() }
                } label: {
                    Label(L("Test"), systemImage: "network")
                }
                .disabled(state.credentialSummary == nil || state.isLoadingRemote)

                Button {
                    Task {
                        await state.saveCredentials(
                            name: accountName,
                            issuerId: issuerId,
                            keyId: keyId,
                            privateKeyPEM: privateKeyPEM
                        )
                        privateKeyPEM = ""
                        loadSummary()
                    }
                } label: {
                    Label(L("Save & Connect"), systemImage: "checkmark.circle")
                }
                .primarySyncButton()
                .disabled(issuerId.isEmpty || keyId.isEmpty || (state.credentialSummary == nil && privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || state.isLoadingRemote)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var adsTab: some View {
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

                Text(L("Apple Ads uses a different key from App Store Connect. Generate an EC P-256 key, upload the public key in Apple Ads → Account Settings → API, then paste Client ID, Team ID, Key ID, and the private key here."))
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
                            importAdsPrivateKey()
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

                    if state.appleAdsCredentialSummary != nil && adsPrivateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L("Private key is stored in Keychain. Leave this empty to keep the current key."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !state.appleAdsAccounts.isEmpty {
                    Picker(L("Ad Account"), selection: Binding(
                        get: { state.selectedAppleAdsAccountId ?? "" },
                        set: { id in
                            guard !id.isEmpty else { return }
                            Task { await state.selectAppleAdsAccount(id) }
                        }
                    )) {
                        ForEach(state.appleAdsAccounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    .labelsHidden()
                }

                if let account = state.appleAdsAccountCapabilities {
                    Text(account.canRunAppStoreCampaigns && account.hasContentProviderDelegation
                         ? L("This ad account can run App Store campaigns.")
                         : L("Check APPSTORE_APP_MANUAL and CONTENT_PROVIDER on this ad account before creating campaigns."))
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
                            || (state.appleAdsCredentialSummary == nil && adsPrivateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            || state.isLoadingAds
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Language")).font(.headline)
                Picker(L("Language"), selection: $uiLanguage) {
                    ForEach(LanguageOption.allCases) { option in
                        Text(option.nativeName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 240)
                .onChange(of: uiLanguage) { _, newValue in
                    let option = LanguageOption(rawValue: newValue) ?? .system
                    LanguageManager.setLanguage(option)
                    LanguageManager.promptRestart()
                }
                Text(L("Language change requires a restart."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Appearance")).font(.headline)
                Picker(L("Appearance"), selection: $appearance) {
                    ForEach(AppearanceOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .onChange(of: appearance) { _, newValue in
                    AppearanceManager.apply(AppearanceOption(rawValue: newValue) ?? .system)
                }
                Text(L("Takes effect immediately — no restart needed."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Behavior")).font(.headline)
                Toggle(L("Strip markdown automatically before sync"), isOn: $stripMarkdown)
                Text(L("Headers, bold, links, and inline code are converted to plain text before a sync request."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var aiTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(L("AI Assistant"), systemImage: state.isAIConfigured || state.isVisionAIConfigured ? "sparkles" : "sparkle.magnifyingglass")
                        .font(.headline)
                    Spacer()
                    if state.isAIRunning {
                        ProgressView().controlSize(.small)
                    }
                }

                Text(L("Use separate AI profiles for text tasks and screenshot image recognition."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                textAISection

                visionAISection

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Total AI calls since install: %d", state.aiCallCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L("Reset")) { state.resetAICallCount() }
                        .controlSize(.small)
                        .disabled(state.aiCallCount == 0)
                }
            }
        }
    }

    private var textAISection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                profileHeader(
                    title: L("Text AI"),
                    subtitle: L("Used for release notes, translation, and App Store copy optimization."),
                    isConfigured: state.isAIConfigured,
                    provider: state.selectedAIProvider,
                    model: state.currentAIModel
                )

                aiProfileFields(
                    provider: $aiProvider,
                    apiKey: $aiApiKey,
                    baseURL: $aiBaseURL,
                    model: $aiModel,
                    role: .text,
                    providers: AIProvider.allCases.filter { $0 != .none }
                ) { newValue in
                    aiBaseURL = state.storedAIBaseURL(for: newValue, role: .text)
                    aiModel = state.storedAIModel(for: newValue, role: .text)
                    aiApiKey = ""
                    aiSaveFeedback = nil
                }

                Text(L("Key is stored in Keychain. Base URL and model are optional — leave empty for the official endpoint and the provider's default model. Override Base URL to point at a proxy / self-hosted gateway (LiteLLM, OneAPI, Helicone, …)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(role: .destructive) {
                        state.removeAIKey(for: aiProvider)
                        state.saveAIEndpointConfig(baseURL: "", model: "", for: aiProvider)
                        aiApiKey = ""
                        aiBaseURL = ""
                        aiModel = ""
                        aiSaveFeedback = nil
                    } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }
                    .disabled(!state.isAIConfigured || state.selectedAIProvider != aiProvider)

                    Spacer()

                    Button {
                        Task {
                            await state.testAIConnection()
                            if let err = state.lastError {
                                aiSaveFeedback = .init(kind: .failure, message: err.message)
                            } else {
                                aiSaveFeedback = .init(kind: .success, message: L("AI provider ready"))
                            }
                        }
                    } label: {
                        Label(L("Test"), systemImage: "network")
                    }
                    .disabled(!state.isAIConfigured || state.isAIRunning)

                    Button {
                        handleAISave()
                    } label: {
                        Label(L("Save"), systemImage: "checkmark.circle")
                    }
                    .primarySyncButton()
                    .disabled(state.isAIRunning)
                }

                feedbackView(aiSaveFeedback)
            }
        }
    }

    private var visionAISection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                profileHeader(
                    title: L("Vision AI"),
                    subtitle: L("Used for screenshot language matching and unassigned image suggestions."),
                    isConfigured: state.isVisionAIConfigured,
                    provider: state.selectedVisionAIProvider,
                    model: state.currentVisionAIModel
                )

                aiProfileFields(
                    provider: $visionAIProvider,
                    apiKey: $visionAIApiKey,
                    baseURL: $visionAIBaseURL,
                    model: $visionAIModel,
                    role: .vision,
                    providers: AIProvider.allCases.filter(\.supportsVisionInput)
                ) { newValue in
                    visionAIBaseURL = state.storedAIBaseURL(for: newValue, role: .vision)
                    visionAIModel = state.storedAIModel(for: newValue, role: .vision)
                    visionAIApiKey = ""
                    visionAISaveFeedback = nil
                }

                Text(L("Use a model that supports image input. This key is stored separately from Text AI, so you can use a cheaper text model and a stronger vision model."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(role: .destructive) {
                        state.removeVisionAIKey(for: visionAIProvider)
                        state.saveAIEndpointConfig(baseURL: "", model: "", for: visionAIProvider, role: .vision)
                        visionAIApiKey = ""
                        visionAIBaseURL = ""
                        visionAIModel = ""
                        visionAISaveFeedback = nil
                    } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }
                    .disabled(!state.isVisionAIConfigured || state.selectedVisionAIProvider != visionAIProvider)

                    Spacer()

                    Button {
                        handleVisionAISave()
                    } label: {
                        Label(L("Save"), systemImage: "checkmark.circle")
                    }
                    .primarySyncButton()
                    .disabled(state.isAIRunning)
                }

                feedbackView(visionAISaveFeedback)
            }
        }
    }

    private func profileHeader(
        title: String,
        subtitle: String,
        isConfigured: Bool,
        provider: AIProvider,
        model: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isConfigured ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isConfigured ? .green : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(isConfigured ? L("Configured (%@)", provider.displayName) : L("Not configured"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isConfigured ? Color.green.opacity(0.14) : Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(isConfigured ? .green : .secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isConfigured {
                    Text(L("Model: %@", model))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
    }

    private func aiProfileFields(
        provider: Binding<AIProvider>,
        apiKey: Binding<String>,
        baseURL: Binding<String>,
        model: Binding<String>,
        role: AIProfileRole,
        providers: [AIProvider],
        onProviderChange: @escaping (AIProvider) -> Void
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text(L("Provider")).foregroundStyle(.secondary)
                Picker("", selection: provider) {
                    ForEach(providers) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                .onChange(of: provider.wrappedValue) { _, newValue in
                    onProviderChange(newValue)
                }
            }
            GridRow {
                Text(L("API Key")).foregroundStyle(.secondary)
                SecureField(provider.wrappedValue.apiKeyPlaceholder, text: apiKey)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text(L("Base URL")).foregroundStyle(.secondary)
                TextField(provider.wrappedValue.defaultBaseURL.absoluteString, text: baseURL)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text(L("Model")).foregroundStyle(.secondary)
                TextField(provider.wrappedValue.defaultModel(for: role), text: model)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private func feedbackView(_ feedback: AISaveFeedback?) -> some View {
        if let feedback {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: feedback.iconName)
                    .foregroundStyle(feedback.tint)
                Text(feedback.message)
                    .font(.caption)
                    .foregroundStyle(feedback.tint)
                Spacer()
            }
            .transition(.opacity)
        }
    }

    private func loadSummary() {
        if let summary = state.credentialSummary {
            accountName = summary.name
            issuerId = summary.issuerId
            keyId = summary.keyId
        }
        if let ads = state.appleAdsCredentialSummary {
            adsName = ads.name
            adsClientId = ads.clientId
            adsTeamId = ads.teamId
            adsKeyId = ads.keyId
        }
        if state.selectedAIProvider != .none {
            aiProvider = state.selectedAIProvider
        }
        aiBaseURL = state.storedAIBaseURL(for: aiProvider, role: .text)
        aiModel = state.storedAIModel(for: aiProvider, role: .text)

        if state.selectedVisionAIProvider != .none {
            visionAIProvider = state.selectedVisionAIProvider
        }
        visionAIBaseURL = state.storedAIBaseURL(for: visionAIProvider, role: .vision)
        visionAIModel = state.storedAIModel(for: visionAIProvider, role: .vision)
    }

    /// https is required so the API key never crosses the wire in cleartext.
    /// http is tolerated only for loopback hosts (local proxies / dev servers).
    private func aiEndpointError(for baseURL: String) -> String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return L("Base URL is not a valid URL.")
        }
        if scheme == "https" { return nil }
        let host = url.host?.lowercased() ?? ""
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if scheme == "http" && isLoopback { return nil }
        return L("Base URL must use https (http is only allowed for localhost).")
    }

    private func handleAISave() {
        if let endpointError = aiEndpointError(for: aiBaseURL) {
            aiSaveFeedback = .init(kind: .failure, message: endpointError)
            return
        }
        // Persist this provider's endpoint config first so the rebuilt
        // service picks up the new Base URL / model.
        state.saveAIEndpointConfig(baseURL: aiBaseURL, model: aiModel, for: aiProvider)

        let trimmedKey = aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let saveErrorBefore = state.lastError
        if !trimmedKey.isEmpty {
            state.saveAIKey(trimmedKey, for: aiProvider)
            aiApiKey = ""
        } else {
            // Endpoint-only update: reload from Keychain so the new URL/model
            // take effect using the previously-saved key for this provider.
            state.reloadAIServiceFromKeychain()
        }

        // Judge THIS save by errors raised during it, not by whatever
        // unrelated error happened to be left in the global banner.
        if state.lastError != saveErrorBefore, let err = state.lastError {
            aiSaveFeedback = .init(kind: .failure, message: err.message)
        } else if state.isAIConfigured && state.selectedAIProvider == aiProvider {
            aiSaveFeedback = .init(
                kind: .success,
                message: L("Saved. Provider: %@", state.selectedAIProvider.displayName)
            )
        } else {
            aiSaveFeedback = .init(
                kind: .failure,
                message: L("Save did not result in a configured provider. Check the Base URL / API key and try again.")
            )
        }
    }

    private func handleVisionAISave() {
        if let endpointError = aiEndpointError(for: visionAIBaseURL) {
            visionAISaveFeedback = .init(kind: .failure, message: endpointError)
            return
        }
        state.saveAIEndpointConfig(
            baseURL: visionAIBaseURL,
            model: visionAIModel,
            for: visionAIProvider,
            role: .vision
        )

        let trimmedKey = visionAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let saveErrorBefore = state.lastError
        if !trimmedKey.isEmpty {
            state.saveVisionAIKey(trimmedKey, for: visionAIProvider)
            visionAIApiKey = ""
        } else {
            state.reloadVisionAIServiceFromKeychain()
        }

        if state.lastError != saveErrorBefore, let err = state.lastError {
            visionAISaveFeedback = .init(kind: .failure, message: err.message)
        } else if state.isVisionAIConfigured && state.selectedVisionAIProvider == visionAIProvider {
            visionAISaveFeedback = .init(
                kind: .success,
                message: L("Saved vision AI. Provider: %@", state.selectedVisionAIProvider.displayName)
            )
        } else {
            visionAISaveFeedback = .init(
                kind: .failure,
                message: L("Save did not result in a configured vision model. Check the API key and try again.")
            )
        }
    }

    private func clearForm() {
        accountName = ""
        issuerId = ""
        keyId = ""
        privateKeyPEM = ""
    }

    private func clearAdsForm() {
        adsName = ""
        adsClientId = ""
        adsTeamId = ""
        adsKeyId = ""
        adsPrivateKeyPEM = ""
    }

    private func importAdsPrivateKey() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.prompt = L("Import")
        OpenPanelPresenter.present(panel) { response, url in
            guard response == .OK, let url else { return }
            Task { @MainActor in
                do {
                    adsPrivateKeyPEM = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    state.handleError(error)
                }
            }
        }
        #endif
    }

    private func importPrivateKey() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.prompt = L("Import")
        OpenPanelPresenter.present(panel) { response, url in
            guard response == .OK, let url else { return }
            Task { @MainActor in
                do {
                    privateKeyPEM = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    state.handleError(error)
                }
            }
        }
        #endif
    }
}

private struct AISaveFeedback {
    enum Kind { case success, failure }
    let kind: Kind
    let message: String

    var iconName: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch kind {
        case .success: return .green
        case .failure: return .red
        }
    }
}
