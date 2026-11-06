import Foundation
import Testing
@testable import ShipNotes

@Suite("AI configuration ordering", .serialized)
@MainActor
struct AIConfigurationConcurrencyTests {
    private func state(store: ControlledAIConfigurationStore) -> AppState {
        let state = AppState(
            aiKeychainStore: store,
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            defaults: makeTestDefaults())
        state.selectedAIProvider = .openai
        state.aiService = state.makeAIService(for: .openai, cachedKey: "fixture-old-key")
        state.selectedVisionAIProvider = .openai
        state.visionAIService = state.makeVisionAIService(for: .openai, cachedKey: "fixture-old-key")
        return state
    }

    private func save(_ key: String, role: AIProfileRole, state: AppState) async -> Bool {
        if role == .text { return await state.saveAIKey(key, for: .openai) }
        return await state.saveVisionAIKey(key, for: .openai)
    }

    private func remove(role: AIProfileRole, state: AppState) async -> Bool {
        if role == .text { return await state.removeAIKey(for: .openai) }
        return await state.removeVisionAIKey(for: .openai)
    }

    private func reload(role: AIProfileRole, state: AppState) async -> Bool {
        if role == .text { return await state.reloadAIServiceFromKeychain() }
        return await state.reloadVisionAIServiceFromKeychain()
    }

    private func requestID(role: AIProfileRole, state: AppState) -> UInt64 {
        role == .text ? state.aiTextConfigurationRequestID : state.aiVisionConfigurationRequestID
    }

    private func isBusy(role: AIProfileRole, state: AppState) -> Bool {
        role == .text ? state.isSavingAIConfiguration : state.isSavingVisionAIConfiguration
    }

    private func isConfigured(role: AIProfileRole, state: AppState) -> Bool {
        role == .text ? state.isAIConfigured : state.isVisionAIConfigured
    }

    @Test(arguments: AIProfileRole.allCases)
    func laterRemovalCannotBeReversedByAnOlderSave(role: AIProfileRole) async {
        let store = ControlledAIConfigurationStore(role: role, block: .save)
        let state = state(store: store)
        defer { store.release() }
        let older = Task { await save("fixture-earlier-save", role: role, state: state) }
        #expect(await waitUntil { store.isBlocked })
        let oldRequestID = requestID(role: role, state: state)
        let newer = Task { await remove(role: role, state: state) }
        #expect(await waitUntil { requestID(role: role, state: state) > oldRequestID })
        #expect(isBusy(role: role, state: state))
        #expect(!store.operations.contains("delete"))

        store.release()
        #expect(await older.value == false)
        #expect(await newer.value)
        #expect(store.key(role: role) == nil)
        #expect(!isConfigured(role: role, state: state))
        #expect(!isBusy(role: role, state: state))
        #expect(store.maximumConcurrentOperations == 1)
        #expect(Array(store.operations.prefix(2)) == ["save", "delete"])
    }

    @Test(arguments: AIProfileRole.allCases)
    func laterSaveWinsAndOlderCompletionDoesNotClearBusyState(role: AIProfileRole) async {
        let store = ControlledAIConfigurationStore(role: role, block: .save, blockEverySave: true)
        let state = state(store: store)
        defer { store.release() }
        let older = Task { await save("fixture-earlier-save", role: role, state: state) }
        #expect(await waitUntil { store.isBlocked })
        let oldRequestID = requestID(role: role, state: state)
        let newer = Task { await save("fixture-latest-save", role: role, state: state) }
        #expect(await waitUntil { requestID(role: role, state: state) > oldRequestID })
        #expect(isBusy(role: role, state: state))
        store.release()

        #expect(await older.value == false)
        #expect(await waitUntil { store.blockedOperationCount == 2 })
        #expect(isBusy(role: role, state: state))
        store.release()
        #expect(await newer.value)
        #expect(store.key(role: role) == "fixture-latest-save")
        #expect(isConfigured(role: role, state: state))
        #expect(!isBusy(role: role, state: state))
        #expect(store.maximumConcurrentOperations == 1)
    }

    @Test(arguments: AIProfileRole.allCases)
    func oldKeychainReadCannotPublishAfterANewerSave(role: AIProfileRole) async {
        let store = ControlledAIConfigurationStore(role: role, block: .load)
        let state = state(store: store)
        defer { store.release() }
        let older = Task { await reload(role: role, state: state) }
        #expect(await waitUntil { store.isBlocked })
        let oldRequestID = requestID(role: role, state: state)
        let newer = Task { await save("fixture-latest-save", role: role, state: state) }
        #expect(await waitUntil { requestID(role: role, state: state) > oldRequestID })
        store.release()

        #expect(await older.value == false)
        #expect(await newer.value)
        #expect(store.key(role: role) == "fixture-latest-save")
        #expect(isConfigured(role: role, state: state))
        #expect(store.maximumConcurrentOperations == 1)
    }

    @Test(arguments: AIProfileRole.allCases)
    func oldKeychainReadCannotReenableARemovedProfile(role: AIProfileRole) async {
        let store = ControlledAIConfigurationStore(role: role, block: .load)
        let state = state(store: store)
        defer { store.release() }
        let older = Task { await reload(role: role, state: state) }
        #expect(await waitUntil { store.isBlocked })
        let oldRequestID = requestID(role: role, state: state)
        let newer = Task { await remove(role: role, state: state) }
        #expect(await waitUntil { requestID(role: role, state: state) > oldRequestID })
        store.release()

        #expect(await older.value == false)
        #expect(await newer.value)
        #expect(!isConfigured(role: role, state: state))
        #expect(store.key(role: role) == nil)
    }

    @Test func failedOldOperationDoesNotPoisonTheQueueOrReplaceNewerSuccess() async {
        let store = ControlledAIConfigurationStore(role: .text, block: .save, rejectSave: true)
        let state = state(store: store)
        defer { store.release() }
        let older = Task { await state.saveAIKey("fixture-rejected-key", for: .openai) }
        #expect(await waitUntil { store.isBlocked })
        let oldRequestID = state.aiTextConfigurationRequestID
        let newer = Task { await state.removeAIKey(for: .openai) }
        #expect(await waitUntil { state.aiTextConfigurationRequestID > oldRequestID })
        store.release()

        #expect(await older.value == false)
        #expect(await newer.value)
        #expect(!state.isAIConfigured)
        #expect(state.lastError == nil)
        #expect(store.key(role: .text) == nil)
    }

    @Test(arguments: AIProfileRole.allCases)
    func startupReloadDoesNotSupersedeAnInProgressUserSave(role: AIProfileRole) async {
        let store = ControlledAIConfigurationStore(role: role, block: .save)
        let state = state(store: store)
        defer { store.release() }
        let saving = Task { await save("fixture-user-save", role: role, state: state) }
        #expect(await waitUntil { store.isBlocked })
        let saveRequestID = requestID(role: role, state: state)
        if role == .text {
            await state.reloadAIServiceFromKeychainInBackground(allowsAuthenticationUI: false)
        } else {
            await state.reloadVisionAIServiceFromKeychainInBackground(allowsAuthenticationUI: false)
        }
        #expect(requestID(role: role, state: state) == saveRequestID)
        store.release()
        #expect(await saving.value)
        #expect(store.key(role: role) == "fixture-user-save")
        #expect(store.operations == ["save"])
    }

    @Test func endpointReloadPrefersTheProviderBeingEdited() async {
        let store = InMemoryAIKeychainStore()
        try? store.save("fixture-anthropic-key", for: .anthropic)
        try? store.save("fixture-openai-key", for: .openai)
        let state = AppState(aiKeychainStore: store, defaults: makeTestDefaults())
        #expect(await state.reloadAIServiceFromKeychain(preferredProvider: .openai))
        #expect(state.selectedAIProvider == .openai)
    }
}

/// Blocking occurs only on the detached persistence worker. Tests release the
/// gate after the later model intent has its request ID, avoiding timing-based
/// guesses about whether two operations actually overlapped.
private final class ControlledAIConfigurationStore: AIKeychainStoring, @unchecked Sendable {
    enum Block { case save, load }
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let blockedRole: AIProfileRole
    private let block: Block
    private let rejectSave: Bool
    private let blockEverySave: Bool
    private var keys: [String: String]
    private var blocked = false
    private var blockedCount = 0
    private var active = 0
    private var maximumActive = 0
    private var recordedOperations: [String] = []

    init(role: AIProfileRole, block: Block, rejectSave: Bool = false, blockEverySave: Bool = false) {
        blockedRole = role
        self.block = block
        self.rejectSave = rejectSave
        self.blockEverySave = blockEverySave
        keys = ["\(role.rawValue):openai": "fixture-old-key"]
    }

    var isBlocked: Bool { lock.withLock { blocked } }
    var blockedOperationCount: Int { lock.withLock { blockedCount } }
    var maximumConcurrentOperations: Int { lock.withLock { maximumActive } }
    var operations: [String] { lock.withLock { recordedOperations } }
    func key(role: AIProfileRole) -> String? { lock.withLock { keys["\(role.rawValue):openai"] } }
    func release() { gate.signal() }

    private func begin(_ operation: String, role: AIProfileRole) {
        let shouldBlock = lock.withLock {
            active += 1
            maximumActive = max(maximumActive, active)
            recordedOperations.append(operation)
            if !blocked || (blockEverySave && operation == "save"), role == blockedRole,
                (operation == "save" && block == .save) || (operation == "load" && block == .load)
            {
                blocked = true
                blockedCount += 1
                return true
            }
            return false
        }
        if shouldBlock { _ = gate.wait(timeout: .now() + 5) }
    }

    private func end() { lock.withLock { active -= 1 } }

    func save(_ apiKey: String, for provider: AIProvider, role: AIProfileRole) throws {
        begin("save", role: role)
        defer { end() }
        if rejectSave { throw AIServiceError.missingAPIKey }
        lock.withLock { keys["\(role.rawValue):\(provider.rawValue)"] = apiKey }
    }

    func load(for provider: AIProvider, role: AIProfileRole) throws -> String? {
        let captured = lock.withLock { keys["\(role.rawValue):\(provider.rawValue)"] }
        begin("load", role: role)
        defer { end() }
        return captured
    }

    func loadWithoutPrompt(for provider: AIProvider, role: AIProfileRole) throws -> String? {
        try load(for: provider, role: role)
    }

    func delete(for provider: AIProvider, role: AIProfileRole) throws {
        begin("delete", role: role)
        defer { end() }
        _ = lock.withLock { keys.removeValue(forKey: "\(role.rawValue):\(provider.rawValue)") }
    }
}
