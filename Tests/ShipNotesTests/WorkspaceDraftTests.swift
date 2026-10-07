import Foundation
import Testing
@testable import ShipNotes

@Suite("Workspace draft persistence")
@MainActor
struct WorkspaceDraftTests {
    private func makeState(
        store: any WorkspaceDraftStoring, account: String = "account-a", version: String = "version-a",
        remoteText: String = "Original remote", remoteKeywords: String = "old,keywords"
    ) -> AppState {
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(), appStoreService: MockASCService(),
            appleAdsCredentialStore: InMemoryAppleAdsCredentialStore(), defaults: makeTestDefaults(),
            workspaceDraftStore: store)
        state.credentialSummary = AppStoreConnectCredentialSummary(
            name: "Fixture", issuerId: account, keyId: "fixture-key")
        state.selectedAppId = "fixture-app"
        state.selectedVersionId = version
        state.remoteNotesByLocale = [
            "en-US": RemoteLocaleNote(
                localizationId: "current-localization", locale: "en-US", text: remoteText,
                storeMetadata: StoreMetadataFields(description: "Original description", keywords: remoteKeywords))
        ]
        state.localeNotes = [
            state.makeNote(
                locale: "en-US", localText: remoteText, remoteNote: state.remoteNotesByLocale["en-US"], path: nil)
        ]
        state.rebuildStoreCopyLocales()
        state.restoreCurrentWorkspaceDraft()
        return state
    }

    @Test func fileStoreRestoresEditsAndSourceWithoutOverwritingFreshRemoteValues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("notes.md")
        try "Fixture source".write(to: source, atomically: true, encoding: .utf8)
        let store = FileWorkspaceDraftStore(directory: directory)
        let first = makeState(store: store)
        first.sourceFolder = source
        first.selectedLocale = "en-US"
        first.workspaceMode = .storeCopy
        first.updateLocalText(for: "en-US", text: "Unsynced release draft")
        first.updateStoreCopyField(for: "en-US", field: .description, text: "Unsynced description")
        first.persistWorkspaceDraftsNow()

        let reopened = makeState(store: store, remoteText: "New remote", remoteKeywords: "fresh,keywords")
        #expect(reopened.localeNotes.first?.localText == "Unsynced release draft")
        #expect(reopened.localeNotes.first?.remoteText == "New remote")
        #expect(reopened.localeNotes.first?.remoteLocalizationId == "current-localization")
        #expect(reopened.storeCopyLocales.first?.localMetadata.description == "Unsynced description")
        #expect(reopened.storeCopyLocales.first?.localMetadata.keywords == "fresh,keywords")
        #expect(reopened.storeCopyLocales.first?.remoteMetadata?.keywords == "fresh,keywords")
        #expect(reopened.sourceFolder == source)
        #expect(reopened.workspaceMode == .storeCopy)
        #expect(reopened.selectedLocale == "en-US")
        #expect(reopened.lastError != nil)
        let serialized = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!serialized.contains("account-a"))
        #expect(!serialized.contains("fixture-key"))
        #expect(!serialized.contains("privateKey"))
    }

    @Test func draftsAreSeparatedByAccountAndVersionAndPreferTheLastWorkspace() {
        let store = InMemoryWorkspaceDraftStore()
        let first = makeState(store: store)
        first.updateLocalText(for: "en-US", text: "Version A draft")
        first.persistWorkspaceDraftsNow()
        let otherVersion = makeState(store: store, version: "version-b")
        #expect(otherVersion.localeNotes.first?.localText == "Original remote")
        otherVersion.updateLocalText(for: "en-US", text: "Version B draft")
        otherVersion.persistWorkspaceDraftsNow()
        let otherAccount = makeState(store: store, account: "account-b")
        #expect(otherAccount.localeNotes.first?.localText == "Original remote")
        #expect(otherAccount.preferredWorkspaceDraftAppID == nil)
        let reopened = makeState(store: store)
        #expect(reopened.localeNotes.first?.localText == "Version A draft")
        #expect(reopened.preferredWorkspaceDraftAppID == "fixture-app")
        #expect(reopened.preferredWorkspaceDraftVersionID(for: "fixture-app") == "version-b")
    }

    @Test func sourceReloadPreservesManualEditsButAcceptsChangesToUntouchedFields() {
        let store = InMemoryWorkspaceDraftStore()
        let state = makeState(store: store)
        // The first imported source is allowed to replace the initial values.
        state.applyImportedReleaseNotes(
            ParsedReleaseNotes(locales: ["en-US": "Imported source"], sourceFiles: [:], sourceDescription: "Fixture"),
            sourceURL: nil)
        #expect(state.localeNotes.first?.localText == "Imported source")
        state.applyImportedReleaseNotes(
            ParsedReleaseNotes(
                locales: ["en-US": "Updated untouched source"], sourceFiles: [:], sourceDescription: "Fixture"),
            sourceURL: nil)
        #expect(state.localeNotes.first?.localText == "Updated untouched source")
        state.updateLocalText(for: "en-US", text: "Manual edit")
        state.updateStoreCopyField(for: "en-US", field: .description, text: "Manual description")
        state.saveCurrentWorkspaceDraft()
        state.localeNotes[0].localText = "External source change"
        state.storeCopyLocales[0].localMetadata.description = "External description change"
        state.storeCopyLocales[0].localMetadata.keywords = "new,source,keywords"
        state.restoreCurrentWorkspaceDraft(afterSourceReload: true)
        #expect(state.localeNotes.first?.localText == "Manual edit")
        #expect(state.storeCopyLocales.first?.localMetadata.description == "Manual description")
        #expect(state.storeCopyLocales.first?.localMetadata.keywords == "new,source,keywords")
        #expect(state.lastError != nil)
    }

    @Test func editsAlreadyPresentOnRemoteAreNotRestoredAsStaleDrafts() {
        let store = InMemoryWorkspaceDraftStore()
        let state = makeState(store: store)
        state.updateLocalText(for: "en-US", text: "Published text")
        state.persistWorkspaceDraftsNow()
        let reopened = makeState(store: store, remoteText: "Published text")
        #expect(reopened.localeNotes.first?.localText == "Published text")
        #expect(reopened.lastError == nil)
        reopened.persistWorkspaceDraftsNow()
        #expect(store.drafts.first?.releaseNotes.isEmpty == true)
    }

    @Test func autosaveCapturesBeforeSwitchingAndCoalescesWrites() async {
        let store = CountingDraftStore()
        let state = makeState(store: store)
        state.updateLocalText(for: "en-US", text: "First edit")
        state.updateLocalText(for: "en-US", text: "Latest edit")
        #expect(store.writeCount == 0)
        // Clear after capturing, as a selection transition would do.
        state.selectedVersionId = "version-b"
        state.localeNotes = []
        state.storeCopyLocales = []
        // Full-suite work can delay execution of the debounce task. Wait for
        // the observable write, and keep the owner alive as the app does.
        #expect(await waitUntil { store.writeCount >= 1 })
        #expect(state.selectedVersionId == "version-b")
        withExtendedLifetime(state) {}
        #expect(store.writeCount == 1)
        #expect(store.drafts.first?.releaseNotes["en-US"]?.text == "Latest edit")
    }

    @Test func applicationTerminationFlushesPendingDraftWithoutAWindow() {
        let store = CountingDraftStore()
        let state = makeState(store: store)
        let delegate = AppDelegate()
        delegate.workspaceState = state
        state.updateLocalText(for: "en-US", text: "Last edit before quitting")
        #expect(store.writeCount == 0)
        delegate.applicationWillTerminate(Notification(name: Notification.Name("FixtureTermination")))
        #expect(store.writeCount == 1)
        #expect(store.drafts.first?.releaseNotes["en-US"]?.text == "Last edit before quitting")
        #expect(state.workspaceDraftSaveTask == nil)
    }

    @Test func screenshotRestoreFiltersReplacedAssetsAndKeepsExistingOrder() {
        let store = InMemoryWorkspaceDraftStore()
        let state = makeState(store: store)
        let folder = URL(fileURLWithPath: "/fixture/screenshots")
        let unchanged = asset(folder: folder, name: "unchanged.png", hash: "unchanged")
        let replaced = asset(folder: folder, name: "replaced.png", hash: "old")
        state.screenshotFolder = folder
        state.screenshotScan = ScreenshotScan(
            inputRoot: folder, root: folder, sourceKind: .directFolder, assets: [unchanged, replaced], skippedCount: 0)
        state.screenshotAILocaleOverrides = [unchanged.id: "en-US", replaced.id: "en-US"]
        state.screenshotAISharedAssetIDs = [unchanged.id, replaced.id]
        state.screenshotOrderByGroup = ["fixture-group": [replaced.id, unchanged.id, "removed.png"]]
        state.persistWorkspaceDraftsNow()
        state.screenshotAILocaleOverrides = [:]
        state.screenshotAISharedAssetIDs = []
        state.screenshotOrderByGroup = [:]
        state.screenshotScan = ScreenshotScan(
            inputRoot: folder, root: folder, sourceKind: .directFolder,
            assets: [unchanged, asset(folder: folder, name: "replaced.png", hash: "new")], skippedCount: 0)
        state.restoreScreenshotWorkspaceDraft()
        #expect(state.screenshotAILocaleOverrides == [unchanged.id: "en-US"])
        #expect(state.screenshotAISharedAssetIDs == [unchanged.id])
        #expect(state.screenshotOrderByGroup["fixture-group"] == [unchanged.id])
    }

    @Test func anEmptyLoadingWorkspaceDoesNotReplaceExistingDrafts() {
        let store = InMemoryWorkspaceDraftStore()
        let state = makeState(store: store)
        state.updateLocalText(for: "en-US", text: "Kept while loading")
        state.persistWorkspaceDraftsNow()
        state.localeNotes = []
        state.storeCopyLocales = []
        state.persistWorkspaceDraftsNow()
        #expect(store.drafts.first?.releaseNotes["en-US"]?.text == "Kept while loading")
    }

    @Test func switchingVersionsWithScreenshotsCannotOverwriteTheLoadingVersionsDraft() {
        let store = InMemoryWorkspaceDraftStore()
        let versionB = makeState(store: store, version: "version-b")
        versionB.updateLocalText(for: "en-US", text: "Saved version B draft")
        versionB.persistWorkspaceDraftsNow()
        let state = makeState(store: store, version: "version-a")
        state.screenshotFolder = URL(fileURLWithPath: "/fixture/version-a-screenshots")
        state.saveCurrentWorkspaceDraft()
        // A version switch clears text immediately while its fetch is pending,
        // but screenshots may still remain from the old version.
        state.selectedVersionId = "version-b"
        state.localeNotes = []
        state.storeCopyLocales = []
        state.persistWorkspaceDraftsNow()
        #expect(
            store.drafts.first { $0.key.versionID == "version-b" }?
                .releaseNotes["en-US"]?.text == "Saved version B draft")

        let remote = RemoteLocaleNote(
            localizationId: "version-b-localization", locale: "en-US", text: "Fresh version B remote")
        state.remoteNotesByLocale = ["en-US": remote]
        state.localeNotes = [state.makeNote(locale: "en-US", localText: remote.text, remoteNote: remote, path: nil)]
        state.rebuildStoreCopyLocales()
        state.restoreCurrentWorkspaceDraft()
        #expect(state.localeNotes.first?.localText == "Saved version B draft")
        #expect(state.localeNotes.first?.remoteText == "Fresh version B remote")
        state.updateLocalText(for: "en-US", text: "New version B edit")
        state.persistWorkspaceDraftsNow()
        #expect(
            store.drafts.first { $0.key.versionID == "version-b" }?
                .releaseNotes["en-US"]?.text == "New version B edit")
    }

    @Test func resolvedAndDifferentWorkspaceConflictsDoNotLeaveStaleWarnings() {
        let state = makeState(store: InMemoryWorkspaceDraftStore())
        state.updateLocalText(for: "en-US", text: "Manual draft")
        state.saveCurrentWorkspaceDraft()
        state.localeNotes[0].remoteText = "External change"
        state.localeNotes[0].localText = "External change"
        state.restoreCurrentWorkspaceDraft()
        #expect(state.workspaceDraftConflictError != nil)
        state.localeNotes[0].remoteText = "Manual draft"
        state.restoreCurrentWorkspaceDraft()
        #expect(state.workspaceDraftConflictError == nil)
        #expect(state.lastError == nil)
        state.workspaceDraftConflictError = "Previous workspace warning"
        state.setError("Previous workspace warning")
        state.selectedVersionId = "different-version"
        state.restoreCurrentWorkspaceDraft()
        #expect(state.workspaceDraftConflictError == nil)
        #expect(state.lastError == nil)
    }

    @Test func saveFailuresKeepThePreviousSnapshotAndRecoverOnRetry() {
        let store = CountingDraftStore()
        let state = makeState(store: store)
        state.updateLocalText(for: "en-US", text: "Previous complete draft")
        state.persistWorkspaceDraftsNow()
        store.failSave = true
        state.updateLocalText(for: "en-US", text: "New edit still in memory")
        state.persistWorkspaceDraftsNow()
        #expect(state.workspaceDraftSaveError != nil)
        #expect(state.lastError?.category == .fileIO)
        #expect(store.drafts.first?.releaseNotes["en-US"]?.text == "Previous complete draft")
        #expect(state.localeNotes.first?.localText == "New edit still in memory")
        store.failSave = false
        state.persistWorkspaceDraftsNow()
        #expect(state.workspaceDraftSaveError == nil)
        #expect(state.lastError == nil)
        #expect(store.drafts.first?.releaseNotes["en-US"]?.text == "New edit still in memory")
    }

    @Test func corruptDraftFileIsReportedAndNeverOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileWorkspaceDraftStore(directory: directory)
        let original = Data("unreadable fixture".utf8)
        try original.write(to: store.fileURL)
        let state = makeState(store: store)
        state.updateLocalText(for: "en-US", text: "Still in memory")
        state.persistWorkspaceDraftsNow()
        #expect(state.workspaceDraftSaveError != nil)
        #expect(state.lastError?.category == .fileIO)
        #expect(try Data(contentsOf: store.fileURL) == original)
        #expect(state.localeNotes.first?.localText == "Still in memory")
    }

    @Test func isolatedDefaultsAutomaticallyUseAnInMemoryDraftStore() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        #expect(state.workspaceDraftStore is InMemoryWorkspaceDraftStore)
        let publicStore = FileWorkspaceDraftStore(applicationIdentifier: "org.example.public")
        let privateStore = FileWorkspaceDraftStore(applicationIdentifier: "org.example.private")
        #expect(publicStore.fileURL != privateStore.fileURL)
    }

    private func asset(folder: URL, name: String, hash: String) -> ScreenshotAsset {
        ScreenshotAsset(
            url: folder.appendingPathComponent(name), relativePath: name,
            size: ScreenshotPixelSize(width: 1242, height: 2688),
            locale: "en-US", deviceSlot: .iPhone65, status: .ready, contentHash: hash)
    }
}

@MainActor
private final class CountingDraftStore: WorkspaceDraftStoring {
    var drafts: [WorkspaceDraft] = []
    var writeCount = 0
    var failSave = false

    func load() throws -> [WorkspaceDraft] { drafts }
    func save(_ drafts: [WorkspaceDraft]) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        writeCount += 1
        self.drafts = drafts
    }
}
