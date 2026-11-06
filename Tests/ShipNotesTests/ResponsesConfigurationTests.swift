import Foundation
import Testing
@testable import ShipNotes

@Suite("Responses configuration")
@MainActor
struct ResponsesConfigurationTests {
    private func state(defaults: UserDefaults, keys: InMemoryAIKeychainStore = .init()) -> AppState {
        AppState(aiKeychainStore: keys, appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(), defaults: defaults)
    }

    @Test func existingProfilesWithoutFormatKeepChatCompletionsAndTheirSettings() async throws {
        let defaults = makeTestDefaults()
        let keys = InMemoryAIKeychainStore()
        defaults.set("https://gateway.example/tenant/v1", forKey: AIProvider.openai.baseURLDefaultsKey)
        defaults.set("legacy-model", forKey: AIProvider.openai.modelDefaultsKey)
        try keys.save("fixture-existing-key", for: .openai, role: .text)
        let state = state(defaults: defaults, keys: keys)

        #expect(state.aiAPIFormat(for: .openai) == .chatCompletions)
        #expect(await state.reloadAIServiceFromKeychain(preferredProvider: .openai))
        let service = try #require(state.aiService as? OpenAIService)
        #expect(service.apiFormat == .chatCompletions)
        #expect(service.baseURL.absoluteString == "https://gateway.example/tenant/v1")
        #expect(service.model == "legacy-model")
        #expect(try keys.load(for: .openai, role: .text) == "fixture-existing-key")
        #expect(defaults.string(forKey: AIProvider.openai.apiFormatDefaultsKey(for: .text)) == nil)
    }

    @Test func textAndVisionFormatsRebuildIndependentlyWithoutChangingKeysOrModels() async throws {
        let defaults = makeTestDefaults()
        let keys = InMemoryAIKeychainStore()
        let state = state(defaults: defaults, keys: keys)
        state.saveAIEndpointConfig(
            baseURL: "https://text.example/v1", model: "text-model", apiFormat: .responses, for: .openai)
        state.saveAIEndpointConfig(
            baseURL: "https://vision.example/v1", model: "vision-model", apiFormat: .chatCompletions, for: .openai,
            role: .vision)
        #expect(await state.saveAIKey("fixture-text-key", for: .openai))
        #expect(await state.saveVisionAIKey("fixture-vision-key", for: .openai))
        let text = try #require(state.aiService as? OpenAIService)
        let vision = try #require(state.visionAIService as? OpenAIScreenshotVisionAIService)
        #expect(text.apiFormat == .responses)
        #expect(vision.apiFormat == .chatCompletions)
        #expect(text.model == "text-model")
        #expect(vision.model == "vision-model")

        state.saveAIEndpointConfig(
            baseURL: "https://vision.example/v1", model: "vision-model", apiFormat: .responses, for: .openai,
            role: .vision)
        #expect(await state.reloadVisionAIServiceFromKeychain(preferredProvider: .openai))
        let updatedVision = try #require(state.visionAIService as? OpenAIScreenshotVisionAIService)
        #expect(updatedVision.apiFormat == .responses)
        #expect(state.aiAPIFormat(for: .openai) == .responses)
        #expect((state.aiService as? OpenAIService)?.baseURL == text.baseURL)
        #expect(updatedVision.model == "vision-model")
        #expect(try keys.load(for: .openai, role: .text) == "fixture-text-key")
        #expect(try keys.load(for: .openai, role: .vision) == "fixture-vision-key")
    }

    @Test(arguments: AIProfileRole.allCases, [false, true])
    func failedKeychainSaveOrReloadRestoresAppliedSettingsAndKeepsTestDisabled(
        role: AIProfileRole, updatingKey: Bool
    ) async {
        let defaults = makeTestDefaults()
        let store = FailingProfileKeychainStore(failSave: updatingKey)
        let state = AppState(
            aiKeychainStore: store, appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(), defaults: defaults)
        state.saveAIEndpointConfig(
            baseURL: "https://old.example/v1", model: "old-model", apiFormat: .chatCompletions, for: .openai, role: role
        )
        if role == .text {
            state.selectedAIProvider = .openai
            state.aiService = state.makeAIService(for: .openai, cachedKey: "fixture-old-key")
        } else {
            state.selectedVisionAIProvider = .openai
            state.visionAIService = state.makeVisionAIService(for: .openai, cachedKey: "fixture-old-key")
        }
        let saved = await state.saveAIProfileConfiguration(
            baseURL: "https://new.example/v1", model: "new-model", apiFormat: .responses,
            apiKeyInput: updatingKey ? "fixture-new-key" : "", for: .openai, role: role)
        #expect(!saved)
        #expect(state.aiAPIFormat(for: .openai, role: role) == .chatCompletions)
        #expect(state.storedAIBaseURL(for: .openai, role: role) == "https://old.example/v1")
        #expect(state.storedAIModel(for: .openai, role: role) == "old-model")
        // Clearing a failed new key must not enable testing the old service
        // with a form that claims to use the new Responses endpoint.
        #expect(
            state.hasUnsavedAIProfileChanges(
                provider: .openai, baseURL: "https://new.example/v1", model: "new-model",
                apiFormat: .responses, apiKeyInput: "", role: role))
        #expect(state.lastError != nil)
        if role == .text {
            #expect((state.aiService as? OpenAIService)?.apiFormat == .chatCompletions)
        } else {
            #expect((state.visionAIService as? OpenAIScreenshotVisionAIService)?.apiFormat == .chatCompletions)
        }
    }

    @Test(arguments: AIProfileRole.allCases)
    func settingsSaveAppliesChosenFormatBeforeEnablingTest(role: AIProfileRole) async {
        let state = state(defaults: makeTestDefaults())
        #expect(
            await state.saveAIProfileConfiguration(
                baseURL: "https://chosen.example/v1", model: "chosen-model", apiFormat: .responses,
                apiKeyInput: "fixture-key", for: .openai, role: role))
        #expect(
            !state.hasUnsavedAIProfileChanges(
                provider: .openai, baseURL: "https://chosen.example/v1", model: "chosen-model",
                apiFormat: .responses, apiKeyInput: "", role: role))
        if role == .text {
            #expect((state.aiService as? OpenAIService)?.apiFormat == .responses)
        } else {
            #expect((state.visionAIService as? OpenAIScreenshotVisionAIService)?.apiFormat == .responses)
        }
    }

    @Test(arguments: AIProfileRole.allCases)
    func staleSaveAndFailedNewerSaveCannotCommitEitherDraftEndpoint(role: AIProfileRole) async {
        let store = ProfileSaveGateStore()
        defer { store.release() }
        let state = AppState(
            aiKeychainStore: store, appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            defaults: makeTestDefaults())
        state.saveAIEndpointConfig(
            baseURL: "https://applied.example/v1", model: "applied-model", apiFormat: .chatCompletions, for: .openai,
            role: role)
        if role == .text {
            state.selectedAIProvider = .openai
            state.aiService = state.makeAIService(for: .openai, cachedKey: "fixture-applied-key")
        } else {
            state.selectedVisionAIProvider = .openai
            state.visionAIService = state.makeVisionAIService(for: .openai, cachedKey: "fixture-applied-key")
        }
        let older = Task {
            await state.saveAIProfileConfiguration(
                baseURL: "https://draft-a.example/v1", model: "draft-a", apiFormat: .responses,
                apiKeyInput: "fixture-older", for: .openai, role: role)
        }
        #expect(await waitUntil { store.isBlocked })
        let oldRequestID = role == .text ? state.aiTextConfigurationRequestID : state.aiVisionConfigurationRequestID
        #expect(state.storedAIBaseURL(for: .openai, role: role) == "https://applied.example/v1")
        let newer = Task {
            await state.saveAIProfileConfiguration(
                baseURL: "https://draft-b.example/v1", model: "draft-b", apiFormat: .responses,
                apiKeyInput: "fixture-newer", for: .openai, role: role)
        }
        #expect(
            await waitUntil {
                (role == .text ? state.aiTextConfigurationRequestID : state.aiVisionConfigurationRequestID)
                    > oldRequestID
            })
        #expect(state.storedAIBaseURL(for: .openai, role: role) == "https://applied.example/v1")
        store.release()
        #expect(await older.value == false)
        #expect(await newer.value == false)
        #expect(state.aiAPIFormat(for: .openai, role: role) == .chatCompletions)
        #expect(state.storedAIBaseURL(for: .openai, role: role) == "https://applied.example/v1")
        #expect(state.storedAIModel(for: .openai, role: role) == "applied-model")
        if role == .text {
            #expect((state.aiService as? OpenAIService)?.apiFormat == .chatCompletions)
        } else {
            #expect((state.visionAIService as? OpenAIScreenshotVisionAIService)?.apiFormat == .chatCompletions)
        }
    }

    @Test func formatKeysAreRoleAndProviderScopedAndUnknownValuesUseLegacyDefault() {
        let defaults = makeTestDefaults()
        let state = state(defaults: defaults)
        let scopedKeys = AIProvider.allCases.flatMap { provider in
            AIProfileRole.allCases.map { provider.apiFormatDefaultsKey(for: $0) }
        }
        #expect(Set(scopedKeys).count == scopedKeys.count)
        defaults.set("future-format", forKey: AIProvider.openai.apiFormatDefaultsKey(for: .text))
        #expect(state.aiAPIFormat(for: .openai) == .chatCompletions)
        state.saveAIEndpointConfig(baseURL: "", model: "", apiFormat: .responses, for: .openai)
        state.saveAIEndpointConfig(baseURL: "", model: "", apiFormat: .responses, for: .anthropic)
        #expect(state.aiAPIFormat(for: .anthropic) == .chatCompletions)
        #expect(state.aiAPIFormat(for: .openai) == .responses)
        #expect(state.aiAPIFormat(for: .openai, role: .vision) == .chatCompletions)
        // Existing callers updating only endpoint/model must not erase format.
        state.saveAIEndpointConfig(baseURL: "https://text.example", model: "kept", for: .openai)
        #expect(state.aiAPIFormat(for: .openai) == .responses)
    }

    @Test func testingRequiresSavingEveryChangedProfileFieldIncludingFormat() {
        let state = state(defaults: makeTestDefaults())
        state.selectedAIProvider = .openai
        state.saveAIEndpointConfig(
            baseURL: "https://text.example/v1", model: "text-model", apiFormat: .responses, for: .openai)
        func dirty(
            provider: AIProvider = .openai, baseURL: String = "https://text.example/v1", model: String = "text-model",
            format: OpenAIAPIFormat = .responses, key: String = ""
        ) -> Bool {
            state.hasUnsavedAIProfileChanges(
                provider: provider, baseURL: baseURL, model: model, apiFormat: format, apiKeyInput: key, role: .text)
        }
        #expect(!dirty())
        #expect(dirty(format: .chatCompletions))
        #expect(dirty(provider: .anthropic))
        #expect(dirty(baseURL: "https://different.example/v1"))
        #expect(dirty(model: "new-model"))
        #expect(dirty(key: "fixture-new-key"))
        #expect(!dirty(baseURL: " https://text.example/v1 ", model: " text-model ", key: " "))
    }

    @Test func endpointPreviewShowsChosenRouteAndRemovesCredentialComponents() {
        let base =
            "https://fixture-user:fixture-password@gateway.example/tenant%2Froute/v1?api_key=fixture-query#fixture-fragment"
        let preview = AIProfileEndpointPreview.url(provider: .openai, baseURL: base, format: .responses)
        #expect(preview == "https://gateway.example/tenant%2Froute/v1/responses")
        #expect(preview?.contains("fixture-") == false)
        #expect(
            AIProfileEndpointPreview.url(provider: .openai, baseURL: "", format: .chatCompletions)
                == "https://api.openai.com/v1/chat/completions")
        #expect(
            AIProfileEndpointPreview.url(provider: .anthropic, baseURL: "", format: .responses)
                == "https://api.anthropic.com/v1/messages")
        #expect(AIProfileEndpointPreview.url(provider: .openai, baseURL: "not a URL", format: .responses) == nil)
    }

    @Test func successfulTextTestReturnsSuccessWhileKeepingAnUnrelatedDraftWarning() async {
        let state = state(defaults: makeTestDefaults())
        state.aiService = MockAIService()
        state.workspaceDraftSaveError = "Fixture draft warning"
        state.setError("Fixture draft warning", category: .fileIO)
        #expect(await state.testAIConnection())
        #expect(state.lastError?.message == "Fixture draft warning")
        #expect(state.aiCallCount == 1)
        #expect(!state.isAIRunning)
    }

    @Test func visionTestCallsOnlyTheConnectionProbeAndDoesNotRequestUserImages() async {
        let counter = VisionProbeCounter()
        let state = state(defaults: makeTestDefaults())
        state.visionAIService = VisionConnectionProbe(counter: counter)
        #expect(await state.testVisionAIConnection())
        #expect(counter.calls == 1)
        #expect(state.aiCallCount == 1)
        #expect(!state.isAIRunning)
    }
}

private final class VisionProbeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func record() { lock.withLock { count += 1 } }
}

private struct VisionConnectionProbe: ScreenshotVisionAIService {
    let counter: VisionProbeCounter
    var isConfigured: Bool { true }
    func testConnection() async throws { counter.record() }
    func classifyScreenshotLocales(
        assets: [ScreenshotAsset], knownLocales: [String], appName: String?
    ) async throws -> [ScreenshotLocaleAssignment] {
        Issue.record("Connection tests must not submit user images")
        return []
    }
}

private struct FailingProfileKeychainStore: AIKeychainStoring {
    let failSave: Bool
    func save(_ apiKey: String, for provider: AIProvider, role: AIProfileRole) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
    }
    func load(for provider: AIProvider, role: AIProfileRole) throws -> String? {
        if !failSave { throw CocoaError(.fileReadNoPermission) }
        return "fixture-old-key"
    }
    func loadWithoutPrompt(for provider: AIProvider, role: AIProfileRole) throws -> String? {
        try load(for: provider, role: role)
    }
    func delete(for provider: AIProvider, role: AIProfileRole) throws {}
}

private final class ProfileSaveGateStore: AIKeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var blocked = false
    var isBlocked: Bool { lock.withLock { blocked } }
    func release() { gate.signal() }
    func save(_ apiKey: String, for provider: AIProvider, role: AIProfileRole) throws {
        if apiKey == "fixture-older" {
            lock.withLock { blocked = true }
            _ = gate.wait(timeout: .now() + 5)
        } else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
    func load(for provider: AIProvider, role: AIProfileRole) throws -> String? { "fixture-applied-key" }
    func loadWithoutPrompt(for provider: AIProvider, role: AIProfileRole) throws -> String? { "fixture-applied-key" }
    func delete(for provider: AIProvider, role: AIProfileRole) throws {}
}
