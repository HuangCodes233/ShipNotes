import SwiftUI

struct AISettingsView: View {
    @Environment(AppState.self) private var state
    @State private var aiProvider: AIProvider = .anthropic
    @State private var aiApiKey: String = ""
    @State private var aiBaseURL: String = ""
    @State private var aiModel: String = ""
    @State private var aiAPIFormat: OpenAIAPIFormat = .chatCompletions
    @State private var aiSaveFeedback: AISaveFeedback?
    @State private var visionAIProvider: AIProvider = .openai
    @State private var visionAIApiKey: String = ""
    @State private var visionAIBaseURL: String = ""
    @State private var visionAIModel: String = ""
    @State private var visionAIAPIFormat: OpenAIAPIFormat = .chatCompletions
    @State private var visionAISaveFeedback: AISaveFeedback?
    @State private var textProfileRequestID: UUID?
    @State private var visionProfileRequestID: UUID?
    // Hydrate once so switching tabs preserves unsaved form values.
    @State private var hasLoadedSummary = false

    @ViewBuilder
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(
                        L("AI Assistant"),
                        systemImage: state.isAIConfigured || state.isVisionAIConfigured
                            ? "sparkles" : "sparkle.magnifyingglass"
                    )
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
        .onAppear(perform: loadSummaryIfNeeded)
    }

    private var textAISection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                AIProfileHeader(
                    title: L("Text AI"),
                    subtitle: L("Used for release notes, translation, and App Store copy optimization."),
                    isConfigured: state.isAIConfigured,
                    provider: state.selectedAIProvider,
                    model: state.currentAIModel
                )

                AIProfileFields(
                    provider: $aiProvider,
                    apiKey: $aiApiKey,
                    baseURL: $aiBaseURL,
                    model: $aiModel,
                    apiFormat: $aiAPIFormat,
                    role: .text,
                    providers: AIProvider.allCases.filter { $0 != .none },
                    onProviderChange: { newValue in
                        aiBaseURL = state.storedAIBaseURL(for: newValue, role: .text)
                        aiModel = state.storedAIModel(for: newValue, role: .text)
                        aiAPIFormat = state.aiAPIFormat(for: newValue, role: .text)
                        aiApiKey = ""
                        aiSaveFeedback = nil
                    }
                )

                Text(
                    L(
                        "Key is stored in Keychain. Base URL and model are optional — leave empty for the official endpoint and the provider's default model. Override Base URL to point at a proxy / self-hosted gateway (LiteLLM, OneAPI, Helicone, …)."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(role: .destructive) {
                        let provider = aiProvider
                        let requestID = UUID()
                        textProfileRequestID = requestID
                        Task {
                            defer { if textProfileRequestID == requestID { textProfileRequestID = nil } }
                            let removed = await state.removeAIKey(for: provider)
                            guard textProfileRequestID == requestID, aiProvider == provider else { return }
                            guard removed else {
                                if let error = state.lastError {
                                    aiSaveFeedback = .init(kind: .failure, message: error.message)
                                }
                                return
                            }
                            state.saveAIEndpointConfig(
                                baseURL: "", model: "", apiFormat: .chatCompletions, for: provider)
                            aiApiKey = ""
                            aiBaseURL = ""
                            aiModel = ""
                            aiAPIFormat = .chatCompletions
                            aiSaveFeedback = nil
                        }
                    } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }
                    .disabled(!state.isAIConfigured || state.selectedAIProvider != aiProvider)

                    Spacer()

                    Button {
                        handleAITest()
                    } label: {
                        Label(L("Test"), systemImage: "network")
                    }
                    .disabled(!state.isAIConfigured || state.isAIRunning || textHasUnsavedChanges)

                    Button {
                        handleAISave()
                    } label: {
                        Label(L("Save"), systemImage: "checkmark.circle")
                    }
                    .primarySyncButton()
                    .disabled(state.isAIRunning)
                }

                if textHasUnsavedChanges {
                    Text(
                        L(
                            "Save changes before testing this profile. The test uses the saved provider, model, and API format."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                feedbackView(aiSaveFeedback)
            }
        }
        .disabled(state.isSavingAIConfiguration || textProfileRequestID != nil)
    }

    private var visionAISection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                AIProfileHeader(
                    title: L("Vision AI"),
                    subtitle: L("Used for screenshot language matching and unassigned image suggestions."),
                    isConfigured: state.isVisionAIConfigured,
                    provider: state.selectedVisionAIProvider,
                    model: state.currentVisionAIModel
                )

                AIProfileFields(
                    provider: $visionAIProvider,
                    apiKey: $visionAIApiKey,
                    baseURL: $visionAIBaseURL,
                    model: $visionAIModel,
                    apiFormat: $visionAIAPIFormat,
                    role: .vision,
                    providers: AIProvider.allCases.filter(\.supportsVisionInput),
                    onProviderChange: { newValue in
                        visionAIBaseURL = state.storedAIBaseURL(for: newValue, role: .vision)
                        visionAIModel = state.storedAIModel(for: newValue, role: .vision)
                        visionAIAPIFormat = state.aiAPIFormat(for: newValue, role: .vision)
                        visionAIApiKey = ""
                        visionAISaveFeedback = nil
                    }
                )

                Text(
                    L(
                        "Use a model that supports image input. This key is stored separately from Text AI, so you can use a cheaper text model and a stronger vision model."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(role: .destructive) {
                        let provider = visionAIProvider
                        let requestID = UUID()
                        visionProfileRequestID = requestID
                        Task {
                            defer { if visionProfileRequestID == requestID { visionProfileRequestID = nil } }
                            let removed = await state.removeVisionAIKey(for: provider)
                            guard visionProfileRequestID == requestID, visionAIProvider == provider else { return }
                            guard removed else {
                                if let error = state.lastError {
                                    visionAISaveFeedback = .init(kind: .failure, message: error.message)
                                }
                                return
                            }
                            state.saveAIEndpointConfig(
                                baseURL: "", model: "", apiFormat: .chatCompletions, for: provider, role: .vision)
                            visionAIApiKey = ""
                            visionAIBaseURL = ""
                            visionAIModel = ""
                            visionAIAPIFormat = .chatCompletions
                            visionAISaveFeedback = nil
                        }
                    } label: {
                        Label(L("Remove"), systemImage: "trash")
                    }
                    .disabled(!state.isVisionAIConfigured || state.selectedVisionAIProvider != visionAIProvider)

                    Spacer()

                    Button {
                        handleVisionAITest()
                    } label: {
                        Label(L("Test"), systemImage: "network")
                    }
                    .disabled(!state.isVisionAIConfigured || state.isAIRunning || visionHasUnsavedChanges)

                    Button {
                        handleVisionAISave()
                    } label: {
                        Label(L("Save"), systemImage: "checkmark.circle")
                    }
                    .primarySyncButton()
                    .disabled(state.isAIRunning)
                }

                if visionHasUnsavedChanges {
                    Text(
                        L(
                            "Save changes before testing this profile. The test uses the saved provider, model, and API format."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                feedbackView(visionAISaveFeedback)
            }
        }
        .disabled(state.isSavingVisionAIConfiguration || visionProfileRequestID != nil)
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

    private func loadSummaryIfNeeded() {
        guard !hasLoadedSummary else { return }
        hasLoadedSummary = true
        loadSummary()
    }

    private func loadSummary() {
        if state.selectedAIProvider != .none {
            aiProvider = state.selectedAIProvider
        }
        aiBaseURL = state.storedAIBaseURL(for: aiProvider, role: .text)
        aiModel = state.storedAIModel(for: aiProvider, role: .text)
        aiAPIFormat = state.aiAPIFormat(for: aiProvider, role: .text)

        if state.selectedVisionAIProvider != .none {
            visionAIProvider = state.selectedVisionAIProvider
        }
        visionAIBaseURL = state.storedAIBaseURL(for: visionAIProvider, role: .vision)
        visionAIModel = state.storedAIModel(for: visionAIProvider, role: .vision)
        visionAIAPIFormat = state.aiAPIFormat(for: visionAIProvider, role: .vision)
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
        guard textProfileRequestID == nil, !state.isSavingAIConfiguration else { return }
        if let endpointError = aiEndpointError(for: aiBaseURL) {
            aiSaveFeedback = .init(kind: .failure, message: endpointError)
            return
        }
        let provider = aiProvider
        let trimmedKey = aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = aiBaseURL
        let model = aiModel
        let format = aiAPIFormat
        let requestID = UUID()
        textProfileRequestID = requestID
        Task {
            defer { if textProfileRequestID == requestID { textProfileRequestID = nil } }
            let saved = await state.saveAIProfileConfiguration(
                baseURL: baseURL, model: model, apiFormat: format, apiKeyInput: trimmedKey,
                for: provider, role: .text)
            guard textProfileRequestID == requestID, aiProvider == provider else { return }

            if saved && state.isAIConfigured && state.selectedAIProvider == provider {
                aiApiKey = ""
                aiSaveFeedback = .init(
                    kind: .success,
                    message: L("Saved. Provider: %@", state.selectedAIProvider.displayName)
                )
            } else {
                aiSaveFeedback = .init(
                    kind: .failure,
                    message: state.lastError?.message
                        ?? L(
                            "Save did not result in a configured provider. Check the Base URL / API key and try again.")
                )
            }
        }
    }

    private func handleVisionAISave() {
        guard visionProfileRequestID == nil, !state.isSavingVisionAIConfiguration else { return }
        if let endpointError = aiEndpointError(for: visionAIBaseURL) {
            visionAISaveFeedback = .init(kind: .failure, message: endpointError)
            return
        }
        let provider = visionAIProvider
        let baseURL = visionAIBaseURL
        let model = visionAIModel
        let format = visionAIAPIFormat
        let trimmedKey = visionAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        visionProfileRequestID = requestID
        Task {
            defer { if visionProfileRequestID == requestID { visionProfileRequestID = nil } }
            let saved = await state.saveAIProfileConfiguration(
                baseURL: baseURL, model: model, apiFormat: format, apiKeyInput: trimmedKey,
                for: provider, role: .vision)
            guard visionProfileRequestID == requestID, visionAIProvider == provider else { return }
            if saved && state.isVisionAIConfigured && state.selectedVisionAIProvider == provider {
                visionAIApiKey = ""
                visionAISaveFeedback = .init(
                    kind: .success,
                    message: L("Saved vision AI. Provider: %@", state.selectedVisionAIProvider.displayName)
                )
            } else {
                visionAISaveFeedback = .init(
                    kind: .failure,
                    message: state.lastError?.message
                        ?? L(
                            "Save did not result in a configured vision model. Check the API key and try again.")
                )
            }
        }
    }

    private var textHasUnsavedChanges: Bool {
        state.hasUnsavedAIProfileChanges(
            provider: aiProvider, baseURL: aiBaseURL, model: aiModel,
            apiFormat: aiAPIFormat, apiKeyInput: aiApiKey, role: .text)
    }

    private var visionHasUnsavedChanges: Bool {
        state.hasUnsavedAIProfileChanges(
            provider: visionAIProvider, baseURL: visionAIBaseURL, model: visionAIModel,
            apiFormat: visionAIAPIFormat, apiKeyInput: visionAIApiKey, role: .vision)
    }

    private func handleAITest() {
        guard !textHasUnsavedChanges, textProfileRequestID == nil else { return }
        let requestID = UUID()
        textProfileRequestID = requestID
        Task {
            defer { if textProfileRequestID == requestID { textProfileRequestID = nil } }
            let succeeded = await state.testAIConnection()
            guard textProfileRequestID == requestID, !textHasUnsavedChanges else { return }
            aiSaveFeedback =
                succeeded
                ? .init(kind: .success, message: L("AI provider ready"))
                : .init(kind: .failure, message: state.lastError?.message ?? L("AI provider connection test failed."))
        }
    }

    private func handleVisionAITest() {
        guard !visionHasUnsavedChanges, visionProfileRequestID == nil else { return }
        let requestID = UUID()
        visionProfileRequestID = requestID
        Task {
            defer { if visionProfileRequestID == requestID { visionProfileRequestID = nil } }
            let succeeded = await state.testVisionAIConnection()
            guard visionProfileRequestID == requestID, !visionHasUnsavedChanges else { return }
            visionAISaveFeedback =
                succeeded
                ? .init(kind: .success, message: L("Vision AI connected (image recognition was not tested)."))
                : .init(kind: .failure, message: state.lastError?.message ?? L("AI provider connection test failed."))
        }
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
