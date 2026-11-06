import Foundation
import Testing
@testable import ShipNotes

@Suite("November workflow regressions")
@MainActor
struct NovemberWorkflowRegressionTests {
    private func makeState(_ service: NovemberWorkflowService) -> AppState {
        let state = AppState(
            credentialStore: NovemberEmptyCredentials(), aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service, appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(),
            defaults: makeTestDefaults(), workspaceDraftStore: InMemoryWorkspaceDraftStore())
        state.credentialSummary = .init(name: "Fixture", issuerId: "fixture-issuer", keyId: "fixture-key")
        state.appStoreConnectionRequestID = UUID()
        state.apps = [
            .init(id: "app", name: "Fixture", bundleId: "example.fixture", platform: "iOS", iconSystemName: "app")
        ]
        state.versionsByApp["app"] = ["A", "B"].map {
            ReleaseVersion(
                id: $0, appId: "app", versionString: "2.0", platform: "iOS", appStoreState: .prepareForSubmission)
        }
        state.selectedAppId = "app"
        state.selectedVersionId = "B"
        let remote = RemoteLocaleNote(
            localizationId: "locale-B", locale: "en-US", text: "Remote B",
            storeMetadata: .init(description: "Remote description"))
        state.remoteNotesByLocale = ["en-US": remote]
        state.localeNotes = [state.makeNote(locale: "en-US", localText: remote.text, remoteNote: remote, path: nil)]
        state.rebuildStoreCopyLocales()
        state.restoreCurrentWorkspaceDraft()
        service.base.fetchedLocalizationsByVersion = [
            "A": [.init(localizationId: "locale-A", locale: "en-US", text: "Remote A")], "B": [remote],
        ]
        service.base.fetchedVersions = state.versionsByApp["app"] ?? []
        return state
    }

    @Test func editingWhileTheBuildLoadsKeepsTheNewestVersionDraft() async {
        let service = NovemberWorkflowService()
        let state = makeState(service)
        state.updateLocalText(for: "en-US", text: "Saved B draft")
        state.persistWorkspaceDraftsNow()
        await state.selectLiveVersion("A", resetSource: true)
        let gate = NovemberWorkflowGate()
        service.buildGate = gate
        let loading = Task { await state.selectLiveVersion("B", resetSource: true) }
        await gate.waitUntilEntered()
        state.updateLocalText(for: "en-US", text: "Newest typed B text")
        state.persistWorkspaceDraftsNow()
        await gate.release()
        await loading.value
        #expect(state.localeNotes.first?.localText == "Newest typed B text")
        #expect(
            state.workspaceDrafts[state.currentWorkspaceDraftKey!]?.releaseNotes["en-US"]?.text == "Newest typed B text"
        )
    }

    @Test(arguments: NovemberReviewMutation.allCases)
    func mutationsDuringTheReleaseTypeRequestAbortBeforeSubmission(_ mutation: NovemberReviewMutation) async {
        let service = NovemberWorkflowService()
        let state = makeState(service)
        let gate = NovemberWorkflowGate()
        service.releaseGate = gate
        let submission = Task { await state.submitSelectedVersionForReview(releaseType: .afterApproval) }
        await gate.waitUntilEntered()
        switch mutation {
        case .releaseNotes:
            state.updateLocalText(for: "en-US", text: "New manual edit")
        case .storeCopy:
            state.updateStoreCopyField(for: "en-US", field: .description, text: "New description")
        case .importedSource:
            state.applyImportedReleaseNotes(
                ParsedReleaseNotes(
                    locales: ["en-US": "New source text"], sourceFiles: [:], sourceDescription: "Fixture"),
                sourceURL: nil)
        case .aiResult:
            // AI and import handlers can assign rows directly rather than using
            // the editor setter; revision tracking must cover that path too.
            state.localeNotes[0].localText = "New AI result"
        case .editThenRevert:
            state.updateLocalText(for: "en-US", text: "Intermediate edit")
            state.updateLocalText(for: "en-US", text: "Remote B")
        case .connection:
            state.appStoreConnectionRequestID = UUID()
        case .account:
            state.credentialSummary = .init(name: "Other", issuerId: "other-issuer", keyId: "other-key")
        case .version:
            state.selectedVersionId = "A"
        case .aiStarted:
            state.isAIRunning = true
        case .sourceImportStarted:
            state.workspaceImportRequestsInFlight = 1
        case .pendingImport:
            state.pendingImport = ParsedReleaseNotes(
                locales: ["en-US": "Pending source"], sourceFiles: [:], sourceDescription: "Fixture")
        }
        await gate.release()
        #expect(await submission.value == false)
        #expect(service.base.submitForReviewCalled == false)
        #expect(state.isFinalizingReviewSubmission == false)
        if mutation == .releaseNotes { #expect(state.localeNotes.first?.localText == "New manual edit") }
        if mutation == .aiResult { #expect(state.localeNotes.first?.localText == "New AI result") }
    }

    @Test func unchangedContentCanStillBeSubmittedAndTheFinalPhaseEnds() async {
        let service = NovemberWorkflowService()
        let state = makeState(service)
        #expect(await state.submitSelectedVersionForReview(releaseType: .afterApproval))
        #expect(service.base.submitForReviewCalled)
        #expect(state.isSubmittingForReview == false)
        #expect(state.isFinalizingReviewSubmission == false)
    }

    @Test func finalSubmissionPhaseCoversTheIrreversibleRequest() async {
        let service = NovemberWorkflowService()
        let state = makeState(service)
        let gate = NovemberWorkflowGate()
        service.submitGate = gate
        let submission = Task { await state.submitSelectedVersionForReview(releaseType: .afterApproval) }
        await gate.waitUntilEntered()
        #expect(state.isFinalizingReviewSubmission)
        state.updateLocalText(for: "en-US", text: "Blocked manual edit")
        state.updateStoreCopyField(for: "en-US", field: .description, text: "Blocked description")
        state.applyImportedReleaseNotes(
            ParsedReleaseNotes(locales: ["en-US": "Blocked import"], sourceFiles: [:], sourceDescription: "Fixture"),
            sourceURL: nil)
        state.selectApp("other-app")
        state.selectVersion("A")
        state.removeCredentials()
        #expect(
            await state.saveCredentials(
                name: "Other", issuerId: "other", keyId: "other", privateKeyPEM: "fixture only",
                candidateService: service) == false)
        #expect(state.reviewBlockedWorkspaceChange)
        #expect(state.localeNotes.first?.localText == "Remote B")
        #expect(state.storeCopyLocales.first?.localMetadata.description == "Remote description")
        #expect(state.selectedAppId == "app")
        #expect(state.selectedVersionId == "B")
        #expect(state.credentialSummary?.issuerId == "fixture-issuer")
        await gate.release()
        #expect(await submission.value)
        #expect(state.isFinalizingReviewSubmission == false)
        #expect(state.lastError != nil)
        state.updateLocalText(for: "en-US", text: "Allowed after finalization")
        #expect(state.localeNotes.first?.localText == "Allowed after finalization")
    }

    @Test(arguments: [true, false])
    func activeImportsAndAIPreventBeginningReview(_ hasImport: Bool) async {
        let service = NovemberWorkflowService()
        let state = makeState(service)
        if hasImport { state.workspaceImportRequestsInFlight = 1 } else { state.isAIRunning = true }
        #expect(await state.submitSelectedVersionForReview(releaseType: .afterApproval) == false)
        #expect(service.base.submitForReviewCalled == false)
        #expect(state.lastError != nil)
    }
}

enum NovemberReviewMutation: CaseIterable, Sendable {
    case releaseNotes, storeCopy, importedSource, aiResult, editThenRevert, connection, account, version
    case aiStarted, sourceImportStarted, pendingImport
}

private struct NovemberEmptyCredentials: AppStoreConnectCredentialStoring {
    func load() throws -> AppStoreConnectCredentials? { nil }
    func save(_ credentials: AppStoreConnectCredentials) throws {}
    func delete() throws {}
}

/// No network client is constructed. Gates make each suspension deterministic
/// without depending on wall-clock sleeps or on the user's configured account.
private final class NovemberWorkflowService: AppStoreConnectServicing, @unchecked Sendable {
    let base = MockASCService()
    var buildGate: NovemberWorkflowGate?
    var releaseGate: NovemberWorkflowGate?
    var submitGate: NovemberWorkflowGate?
    func validateCredentials() async throws { try await base.validateCredentials() }
    func fetchApps() async throws -> [AppRecord] { try await base.fetchApps() }
    func fetchVersions(appId: String) async throws -> [ReleaseVersion] { try await base.fetchVersions(appId: appId) }
    func fetchLocalizations(versionId: String) async throws -> [RemoteLocaleNote] {
        try await base.fetchLocalizations(versionId: versionId)
    }
    func updateWhatsNew(localizationId: String, text: String) async throws -> RemoteLocaleNote {
        try await base.updateWhatsNew(localizationId: localizationId, text: text)
    }
    func updateStoreMetadata(localizationId: String, metadata: StoreMetadataFields) async throws -> RemoteLocaleNote {
        try await base.updateStoreMetadata(localizationId: localizationId, metadata: metadata)
    }
    func updateStoreMetadataField(
        localizationId: String, field: StoreCopyField, value: String
    ) async throws -> RemoteLocaleNote {
        try await base.updateStoreMetadataField(localizationId: localizationId, field: field, value: value)
    }
    func createLocalization(versionId: String, locale: String, text: String) async throws -> RemoteLocaleNote {
        try await base.createLocalization(versionId: versionId, locale: locale, text: text)
    }
    func createVersion(appId: String, versionString: String, platform: String) async throws -> ReleaseVersion {
        try await base.createVersion(appId: appId, versionString: versionString, platform: platform)
    }
    func fetchBuilds(appId: String, marketingVersion: String) async throws -> [Build] {
        try await base.fetchBuilds(appId: appId, marketingVersion: marketingVersion)
    }
    func fetchAllBuilds(appId: String) async throws -> [Build] { try await base.fetchAllBuilds(appId: appId) }
    func fetchAttachedBuild(versionId: String) async throws -> Build? {
        if let buildGate { await buildGate.hold() }
        return try await base.fetchAttachedBuild(versionId: versionId)
    }
    func setBuild(_ buildId: String?, forVersion versionId: String) async throws {
        try await base.setBuild(buildId, forVersion: versionId)
    }
    func updateVersion(versionId: String, releaseType: String?) async throws {
        if let releaseGate { await releaseGate.hold() }
        try await base.updateVersion(versionId: versionId, releaseType: releaseType)
    }
    func replaceScreenshots(
        localizationId: String, displayType: String, files: [URL], onProgress: (@Sendable (Int, Int, String) -> Void)?
    ) async throws -> Int {
        try await base.replaceScreenshots(
            localizationId: localizationId, displayType: displayType, files: files, onProgress: onProgress)
    }
    func fetchScreenshotSets(localizationId: String) async throws -> [RemoteScreenshotSet] {
        try await base.fetchScreenshotSets(localizationId: localizationId)
    }
    func submitForReview(appId: String, versionId: String, platform: String) async throws -> String {
        if let submitGate { await submitGate.hold() }
        return try await base.submitForReview(appId: appId, versionId: versionId, platform: platform)
    }
}

private actor NovemberWorkflowGate {
    private var entered = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var workWaiter: CheckedContinuation<Void, Never>?
    func hold() async {
        entered = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        await withCheckedContinuation { continuation in
            if released { continuation.resume() } else { workWaiter = continuation }
        }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func release() {
        released = true
        workWaiter?.resume()
        workWaiter = nil
    }
}
