import Foundation
import Testing
@testable import ShipNotes

/// Each state uses isolated defaults and in-memory credential stores. Candidate
/// clients are injected directly, so these regressions cannot reach the network
/// or the user's Keychain, even when exercising startup and account replacement.
@Suite("Reliable workspace workflows")
@MainActor
struct ReliabilityWorkflowTests {
    private func makeState(
        service: MockASCService = MockASCService(), store: ReliabilityCredentialStore = ReliabilityCredentialStore()
    ) -> AppState {
        let state = AppState(
            credentialStore: store,
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            defaults: makeTestDefaults()
        )
        state.apps = [
            AppRecord(id: "app-1", name: "Demo", bundleId: "example.demo", platform: "iOS", iconSystemName: "app")
        ]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.1", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.localeNotes = [
            LocaleNote(
                locale: "en-US", remoteLocalizationId: "loc-en", localText: "Outgoing notes",
                remoteText: "Remote notes", status: .ready, diffSummary: nil)
        ]
        service.fetchedVersions = state.versionsByApp["app-1"] ?? []
        service.fetchedLocalizations = [
            RemoteLocaleNote(localizationId: "loc-en", locale: "en-US", text: "Remote notes")
        ]
        return state
    }

    @Test func syncKeepsTextTypedWhileTheRequestWasInFlight() async {
        let service = MockASCService()
        service.updateWhatsNewDelayNanoseconds = 200_000_000
        let state = makeState(service: service)
        let running = Task { await state.performSyncAsync() }
        #expect(await waitUntil { state.localeNotes.first?.status == .syncing })
        state.updateLocalText(for: "en-US", text: "Newer user draft")
        await running.value

        #expect(service.lastUpdatedWhatsNew?.text == "Outgoing notes")
        #expect(state.localeNotes.first?.localText == "Newer user draft")
        #expect(state.localeNotes.first?.remoteText == "Outgoing notes")
        #expect(state.localeNotes.first?.status == .ready)
        #expect(state.localeNotes.first?.diffSummary?.hasChanges == true)
    }

    @Test func secondSubmitAttemptRetriesThePreviouslyFailedReleaseNotes() async {
        let service = MockASCService()
        let state = makeState(service: service)
        service.updateWhatsNewError = AppStoreConnectClientError.requestFailed(statusCode: 500, message: "offline")
        #expect(await state.submitSelectedVersionForReview(releaseType: nil) == false)
        #expect(await state.submitSelectedVersionForReview(releaseType: nil) == false)
        #expect(service.submitForReviewCalled == false)

        service.updateWhatsNewError = nil
        #expect(await state.submitSelectedVersionForReview(releaseType: nil))
        #expect(service.lastUpdatedWhatsNew?.text == "Outgoing notes")
        #expect(service.submitForReviewCalled)
    }

    @Test func previouslyFailedStoreCopyIsRetriedBeforeSubmitting() async {
        let service = MockASCService()
        let state = makeState(service: service)
        state.localeNotes = []
        let remote = RemoteLocaleNote(
            localizationId: "loc-en", locale: "en-US", text: "",
            storeMetadata: StoreMetadataFields(description: "Old description"))
        state.storeCopyLocales = [
            state.makeStoreCopy(
                locale: "en-US", localMetadata: StoreMetadataFields(description: "New description"), remoteNote: remote)
        ]
        service.updateStoreMetadataError = AppStoreConnectClientError.requestFailed(statusCode: 500, message: "offline")
        #expect(await state.submitSelectedVersionForReview(releaseType: nil) == false)
        #expect(await state.submitSelectedVersionForReview(releaseType: nil) == false)
        #expect(service.submitForReviewCalled == false)

        service.updateStoreMetadataError = nil
        #expect(await state.submitSelectedVersionForReview(releaseType: nil))
        #expect(service.lastUpdatedStoreMetadata?.description == "New description")
    }

    @Test func invalidAndOversizedDraftsCannotBeSkippedBySubmission() async {
        let service = MockASCService()
        let state = makeState(service: service)
        state.updateLocalText(
            for: "en-US", text: String(repeating: "x", count: ValidationEngine.whatsNewCharacterLimit + 1))
        #expect(await state.submitSelectedVersionForReview(releaseType: nil) == false)
        #expect(service.submitForReviewCalled == false)

        state.localeNotes = []
        let metadata = StoreMetadataFields(description: "New description", supportURL: "not-a-url")
        let remote = RemoteLocaleNote(
            localizationId: "loc-en", locale: "en-US", text: "",
            storeMetadata: StoreMetadataFields(description: "Old description"))
        state.storeCopyLocales = [state.makeStoreCopy(locale: "en-US", localMetadata: metadata, remoteNote: remote)]
        #expect(state.storeCopyLocales.first?.status == .invalid)
        #expect(await state.submitSelectedVersionForReview(releaseType: nil) == false)
        #expect(service.submitForReviewCalled == false)
        #expect(service.lastUpdatedStoreMetadata == nil)
    }

    @Test func submitDoesNotLockTheVersionWhenTextWasEditedDuringAutoSync() async {
        let service = MockASCService()
        service.updateWhatsNewDelayNanoseconds = 200_000_000
        let state = makeState(service: service)
        let submit = Task { await state.submitSelectedVersionForReview(releaseType: nil) }
        #expect(await waitUntil { state.localeNotes.first?.status == .syncing })
        state.updateLocalText(for: "en-US", text: "Newer draft needs another review")
        #expect(await submit.value == false)
        #expect(service.submitForReviewCalled == false)
        #expect(state.localeNotes.first?.localText == "Newer draft needs another review")
    }

    @Test func reselectingTheCurrentLiveAppAndVersionDoesNotReloadOrClearDrafts() async {
        let service = MockASCService()
        let state = makeState(service: service)
        state.sourceFolder = URL(fileURLWithPath: "/tmp/source-placeholder.md")
        let generation = state.syncGeneration
        await state.selectLiveApp("app-1")
        await state.selectLiveVersion("v-1", resetSource: true)

        #expect(state.localeNotes.first?.localText == "Outgoing notes")
        #expect(state.sourceFolder?.lastPathComponent == "source-placeholder.md")
        #expect(state.syncGeneration == generation)
        #expect(service.fetchLocalizationsCallCount == 0)
        #expect(service.fetchAttachedBuildCallCount == 0)
    }

    @Test func reselectingTheCurrentSampleSelectionKeepsManualEdits() {
        let state = makeState()
        state.bootstrapWithMockData()
        guard let appID = state.selectedAppId, let versionID = state.selectedVersionId,
            let locale = state.localeNotes.first?.locale
        else {
            Issue.record("Sample data must select a workspace")
            return
        }
        state.updateLocalText(for: locale, text: "Manual sample edit")
        state.selectMockApp(appID)
        state.selectMockVersion(versionID)
        #expect(state.localeNotes.first { $0.locale == locale }?.localText == "Manual sample edit")
    }

    @Test func startupRunsOnlyOnceForTheSharedState() async {
        let store = ReliabilityCredentialStore()
        let state = makeState(store: store)
        await state.bootstrapForLaunch()
        #expect(await waitUntil { store.loadCount > 0 })
        guard let locale = state.localeNotes.first?.locale else {
            Issue.record("Startup must load sample notes")
            return
        }
        state.updateLocalText(for: locale, text: "Draft survives another window")
        let loadCount = store.loadCount
        await state.bootstrapForLaunch()
        #expect(state.localeNotes.first { $0.locale == locale }?.localText == "Draft survives another window")
        #expect(store.loadCount == loadCount)
    }

    @Test func switchingLiveVersionsClearsTheOldStoreCopySourceAndRestoresOnlyItsOwnDraft() async throws {
        let service = MockASCService()
        let state = makeState(service: service)
        state.credentialSummary = AppStoreConnectCredentialSummary(
            name: "Fixture", issuerId: "fixture-issuer", keyId: "fixture-key")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceA = directory.appendingPathComponent("version-a.txt")
        let sourceB = directory.appendingPathComponent("version-b.txt")
        try "Source A".write(to: sourceA, atomically: true, encoding: .utf8)
        try "Source B".write(to: sourceB, atomically: true, encoding: .utf8)
        let remoteA = RemoteLocaleNote(
            localizationId: "loc-a", locale: "en-US", text: "Remote A",
            storeMetadata: StoreMetadataFields(description: "Description A"))
        let remoteB = RemoteLocaleNote(
            localizationId: "loc-b", locale: "en-US", text: "Remote B",
            storeMetadata: StoreMetadataFields(description: "Description B"))
        service.fetchedLocalizationsByVersion = ["v-1": [remoteA], "v-2": [remoteB]]
        state.versionsByApp["app-1"]?.append(
            ReleaseVersion(
                id: "v-2", appId: "app-1", versionString: "2.0", platform: "iOS", appStoreState: .prepareForSubmission))
        state.storeCopyLocales = [
            state.makeStoreCopy(locale: "en-US", localMetadata: remoteA.storeMetadata, remoteNote: remoteA)
        ]
        state.restoreCurrentWorkspaceDraft()
        state.storeCopySourceURL = sourceA
        state.storeCopySourceDescription = "Source A"
        state.updateStoreCopyField(for: "en-US", field: .description, text: "Draft A")

        await state.selectLiveVersion("v-2", resetSource: true)
        #expect(state.storeCopySourceURL == nil)
        #expect(state.storeCopySourceDescription == nil)
        #expect(state.storeCopyLocales.first?.localMetadata.description == "Description B")

        state.storeCopySourceURL = sourceB
        state.storeCopySourceDescription = "Source B"
        state.updateStoreCopyField(for: "en-US", field: .description, text: "Draft B")
        await state.selectLiveVersion("v-1", resetSource: true)
        #expect(state.storeCopySourceURL == sourceA)
        #expect(state.storeCopyLocales.first?.localMetadata.description == "Draft A")
        await state.selectLiveVersion("v-2", resetSource: true)
        #expect(state.storeCopySourceURL == sourceB)
        #expect(state.storeCopyLocales.first?.localMetadata.description == "Draft B")
    }

    @Test func switchingSampleVersionsDoesNotCarryStoreCopyFromAnotherVersion() {
        let state = makeState()
        state.bootstrapWithMockData()
        guard let appID = state.selectedAppId, let firstVersionID = state.selectedVersionId,
            let secondVersion = state.versionsByApp[appID]?.first(where: { $0.id != firstVersionID }),
            let locale = state.storeCopyLocales.first?.locale
        else {
            Issue.record("Sample data must contain two versions and store copy")
            return
        }
        state.storeCopySourceURL = URL(fileURLWithPath: "/tmp/old-sample-source.txt")
        state.storeCopySourceDescription = "Old sample source"
        state.updateStoreCopyField(for: locale, field: .description, text: "First version draft")
        state.selectMockVersion(secondVersion.id)
        #expect(state.storeCopySourceURL == nil)
        #expect(state.storeCopySourceDescription == nil)
        #expect(state.storeCopyLocales.allSatisfy { $0.localMetadata.description != "First version draft" })

        let copy = state.makeStoreCopy(
            locale: locale, localMetadata: StoreMetadataFields(description: "Second version draft"), remoteNote: nil)
        state.storeCopyLocales = [copy]
        state.scheduleWorkspaceDraftSave()
        state.selectMockVersion(firstVersionID)
        #expect(
            state.storeCopyLocales.first { $0.locale == locale }?.localMetadata.description == "First version draft")
        state.selectMockVersion(secondVersion.id)
        #expect(
            state.storeCopyLocales.first { $0.locale == locale }?.localMetadata.description == "Second version draft")
    }

    @Test func aDraftConflictSurvivesUnrelatedSuccessAndClearsAfterSync() async {
        let service = MockASCService()
        let state = makeState(service: service)
        let conflict = "Fixture draft conflict"
        state.workspaceDraftConflictError = conflict
        state.setError(conflict)
        await state.refreshAttachedBuild(versionId: "v-1", surfaceErrors: true)
        #expect(state.lastError?.message == conflict)
        await state.performSyncAsync()
        #expect(state.localeNotes.first?.localText == state.localeNotes.first?.remoteText)
        #expect(state.workspaceDraftConflictError == nil)
        #expect(state.lastError == nil)
    }

    @Test(arguments: [ReliabilityCandidateFailure.validation, .appList])
    func rejectedCandidatePreservesTheOldCredentialsConnectionAndDrafts(
        _ failure: ReliabilityCandidateFailure
    ) async throws {
        let old = AppStoreConnectCredentials(
            name: "Old", issuerId: "old-issuer", keyId: "old-key", privateKeyPEM: "in-memory old key")
        let store = ReliabilityCredentialStore(credentials: old)
        let service = MockASCService()
        let state = makeState(service: service, store: store)
        state.credentialSummary = old.summary
        state.accounts = [state.account(from: old)]
        let oldStatus = state.connectionStatus

        let saved = await state.saveCredentials(
            name: "Candidate", issuerId: "new-issuer", keyId: "new-key", privateKeyPEM: "in-memory candidate key",
            candidateService: ReliabilityRejectedCandidate(failure: failure))

        #expect(saved == false)
        #expect(try store.load() == old)
        #expect(store.saveCount == 0)
        #expect(state.credentialSummary == old.summary)
        #expect((state.appStoreService as? MockASCService) === service)
        #expect(state.connectionStatus == oldStatus)
        #expect(state.selectedVersionId == "v-1")
        #expect(state.localeNotes.first?.localText == "Outgoing notes")
        #expect(state.lastError != nil)
    }

    @Test func keychainSaveFailureDoesNotInstallTheValidatedCandidate() async throws {
        let old = AppStoreConnectCredentials(
            name: "Old", issuerId: "old-issuer", keyId: "old-key", privateKeyPEM: "in-memory old key")
        let store = ReliabilityCredentialStore(credentials: old)
        store.rejectSaves = true
        let oldService = MockASCService()
        let state = makeState(service: oldService, store: store)
        state.credentialSummary = old.summary
        let candidate = MockASCService()
        candidate.fetchedApps = state.apps

        #expect(
            await state.saveCredentials(
                name: "Candidate", issuerId: "new-issuer", keyId: "new-key", privateKeyPEM: "in-memory candidate key",
                candidateService: candidate) == false)
        #expect(try store.load() == old)
        #expect(state.credentialSummary == old.summary)
        #expect((state.appStoreService as? MockASCService) === oldService)
        #expect(state.localeNotes.first?.localText == "Outgoing notes")
    }

    @Test func successfulCandidateCommitsAndLoadsItsOwnWorkspace() async throws {
        let store = ReliabilityCredentialStore()
        let state = makeState(store: store)
        let candidate = MockASCService()
        candidate.fetchedApps = [
            AppRecord(
                id: "new-app", name: "Candidate App", bundleId: "example.candidate", platform: "iOS",
                iconSystemName: "app")
        ]
        candidate.fetchedVersions = [
            ReleaseVersion(
                id: "new-v", appId: "new-app", versionString: "2.0", platform: "iOS",
                appStoreState: .prepareForSubmission)
        ]
        candidate.fetchedLocalizations = [
            RemoteLocaleNote(localizationId: "new-loc", locale: "en-US", text: "Candidate remote notes")
        ]

        #expect(
            await state.saveCredentials(
                name: "Candidate", issuerId: "new-issuer", keyId: "new-key", privateKeyPEM: "in-memory candidate key",
                candidateService: candidate))
        #expect(store.saveCount == 1)
        #expect(try store.load()?.keyId == "new-key")
        #expect((state.appStoreService as? MockASCService) === candidate)
        #expect(state.selectedAppId == "new-app")
        #expect(state.selectedVersionId == "new-v")
        #expect(state.localeNotes.first?.localText == "Candidate remote notes")
        #expect(state.isUsingMockData == false)
        #expect(state.lastError == nil)
    }

    @Test(arguments: [false, true])
    func aLateAppRefreshCannotPolluteAReplacementAccount(_ oldRefreshFails: Bool) async throws {
        let oldCredentials = AppStoreConnectCredentials(
            name: "Old", issuerId: "old-issuer", keyId: "old-key", privateKeyPEM: "in-memory fixture")
        let store = ReliabilityCredentialStore(credentials: oldCredentials)
        let state = makeState(store: store)
        state.credentialSummary = oldCredentials.summary
        state.appStoreConnectionRequestID = UUID()
        let gate = ReliabilityRefreshGate()
        state.appStoreService = ReliabilityRejectedCandidate(
            failure: .appList, refreshGate: gate, returnedApps: oldRefreshFails ? nil : state.apps)
        let oldRefresh = Task { await state.refreshApps() }
        await gate.waitUntilStarted()

        let candidate = MockASCService()
        candidate.fetchedApps = [
            AppRecord(id: "new-app", name: "New", bundleId: "example.new", platform: "iOS", iconSystemName: "app")
        ]
        candidate.fetchedVersions = [
            ReleaseVersion(
                id: "new-version", appId: "new-app", versionString: "2.0", platform: "iOS",
                appStoreState: .prepareForSubmission)
        ]
        candidate.fetchedLocalizations = [
            RemoteLocaleNote(localizationId: "new-localization", locale: "en-US", text: "New remote")
        ]
        #expect(
            await state.saveCredentials(
                name: "New", issuerId: "new-issuer", keyId: "new-key", privateKeyPEM: "in-memory new fixture",
                candidateService: candidate))
        state.updateLocalText(for: "en-US", text: "New account draft")
        state.setError("New account warning")
        // Represent another operation owned by the installed connection. The
        // stale refresh's defer must not clear its loading indicator either.
        state.isLoadingRemote = true
        await gate.release()
        #expect(await oldRefresh.value == false)
        #expect(state.apps.map(\.id) == ["new-app"])
        #expect(state.selectedAppId == "new-app")
        #expect(state.selectedVersionId == "new-version")
        #expect(state.credentialSummary?.issuerId == "new-issuer")
        #expect(state.localeNotes.first?.localText == "New account draft")
        #expect(state.lastError?.message == "New account warning")
        #expect(state.isLoadingRemote)
        #expect((state.appStoreService as? MockASCService) === candidate)
        state.persistWorkspaceDraftsNow()
        let accountID = try #require(state.workspaceDraftAccountID)
        #expect(
            state.workspaceDrafts.values.filter { $0.key.accountID == accountID }.allSatisfy {
                $0.key.appID == "new-app" && $0.key.versionID == "new-version"
            })
        state.isLoadingRemote = false
    }
}

private final class ReliabilityCredentialStore: AppStoreConnectCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: AppStoreConnectCredentials?
    private var loads = 0
    private var saves = 0
    var rejectSaves = false
    var loadCount: Int { lock.withLock { loads } }
    var saveCount: Int { lock.withLock { saves } }
    init(credentials: AppStoreConnectCredentials? = nil) { self.credentials = credentials }
    func load() throws -> AppStoreConnectCredentials? {
        lock.withLock {
            loads += 1; return credentials
        }
    }
    func save(_ credentials: AppStoreConnectCredentials) throws {
        try lock.withLock {
            if rejectSaves { throw AppStoreConnectCredentialError.keychainSaveFailed(-1) }
            saves += 1
            self.credentials = credentials
        }
    }
    func delete() throws { lock.withLock { credentials = nil } }
}

enum ReliabilityCandidateFailure: Error, Sendable, Equatable {
    case validation
    case appList
    case unexpectedOperation
}

/// This fake has no HTTP client at all. An unexpected post-validation call
/// fails immediately rather than falling back to any live service.
private struct ReliabilityRejectedCandidate: AppStoreConnectServicing {
    let failure: ReliabilityCandidateFailure
    var refreshGate: ReliabilityRefreshGate? = nil
    var returnedApps: [AppRecord]? = nil
    func validateCredentials() async throws { if failure == .validation { throw failure } }
    func fetchApps() async throws -> [AppRecord] {
        if let refreshGate {
            await refreshGate.wait()
            if let returnedApps { return returnedApps }
        }
        throw failure
    }
    func fetchVersions(appId: String) async throws -> [ReleaseVersion] {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func fetchLocalizations(versionId: String) async throws -> [RemoteLocaleNote] {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func updateWhatsNew(localizationId: String, text: String) async throws -> RemoteLocaleNote {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func updateStoreMetadata(localizationId: String, metadata: StoreMetadataFields) async throws -> RemoteLocaleNote {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func updateStoreMetadataField(
        localizationId: String, field: StoreCopyField, value: String
    ) async throws -> RemoteLocaleNote { throw ReliabilityCandidateFailure.unexpectedOperation }
    func createLocalization(versionId: String, locale: String, text: String) async throws -> RemoteLocaleNote {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func createVersion(appId: String, versionString: String, platform: String) async throws -> ReleaseVersion {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func fetchBuilds(appId: String, marketingVersion: String) async throws -> [Build] {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func fetchAllBuilds(appId: String) async throws -> [Build] { throw ReliabilityCandidateFailure.unexpectedOperation }
    func fetchAttachedBuild(versionId: String) async throws -> Build? {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func setBuild(_ buildId: String?, forVersion versionId: String) async throws {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func updateVersion(versionId: String, releaseType: String?) async throws {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func replaceScreenshots(
        localizationId: String, displayType: String, files: [URL], onProgress: (@Sendable (Int, Int, String) -> Void)?
    ) async throws -> Int { throw ReliabilityCandidateFailure.unexpectedOperation }
    func resumeScreenshotProcessing(_ reservation: ScreenshotProcessingReservation) async throws -> Int {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func fetchScreenshotSets(localizationId: String) async throws -> [RemoteScreenshotSet] {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
    func submitForReview(appId: String, versionId: String, platform: String) async throws -> String {
        throw ReliabilityCandidateFailure.unexpectedOperation
    }
}

/// Hold the old account's response until the replacement has been committed;
/// this makes both stale-success and stale-error paths deterministic.
private actor ReliabilityRefreshGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var responseWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        await withCheckedContinuation { continuation in
            if released { continuation.resume() } else { responseWaiter = continuation }
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        responseWaiter?.resume()
        responseWaiter = nil
    }
}
