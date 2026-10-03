import SwiftUI

struct AISettingsView: View {
    @Environment(AppState.self) private var state
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
                    role: .text,
                    providers: AIProvider.allCases.filter { $0 != .none },
                    onProviderChange: { newValue in
                        aiBaseURL = state.storedAIBaseURL(for: newValue, role: .text)
                        aiModel = state.storedAIModel(for: newValue, role: .text)
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
                    role: .vision,
                    providers: AIProvider.allCases.filter(\.supportsVisionInput),
                    onProviderChange: { newValue in
                        visionAIBaseURL = state.storedAIBaseURL(for: newValue, role: .vision)
                        visionAIModel = state.storedAIModel(for: newValue, role: .vision)
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
