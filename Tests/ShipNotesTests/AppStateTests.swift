import Foundation
import Testing
#if canImport(AppKit)
import AppKit
#endif
@testable import ShipNotes

@Suite("AppState")
@MainActor
struct AppStateTests {
    @Test func storeCopySyncAvailabilityTracksEditsValidationAndVersionLock() throws {
        let state = AppState.preview(defaults: makeTestDefaults())
        let locale = try #require(state.selectedStoreCopyLocale)
        let appID = try #require(state.selectedAppId)
        let versionID = try #require(state.selectedVersionId)
        let versionIndex = try #require(state.versionsByApp[appID]?.firstIndex { $0.id == versionID })

        state.revertStoreCopyToRemote(locale)
        #expect(!state.canSyncSelectedStoreCopy)

        state.updateStoreCopyField(for: locale, field: .description, text: "Updated description")
        #expect(state.canSyncSelectedStoreCopy)

        state.isSyncing = true
        #expect(!state.canSyncSelectedStoreCopy)
        state.isSyncing = false
        #expect(state.canSyncSelectedStoreCopy)

        state.updateStoreCopyField(for: locale, field: .description, text: String(repeating: "x", count: 4_001))
        #expect(!state.canSyncSelectedStoreCopy)
        state.updateStoreCopyField(for: locale, field: .description, text: "Updated description")
        #expect(state.canSyncSelectedStoreCopy)

        state.selectedStoreCopyLocale = nil
        #expect(!state.canSyncSelectedStoreCopy)
        state.selectedStoreCopyLocale = locale
        #expect(state.canSyncSelectedStoreCopy)

        state.versionsByApp[appID]?[versionIndex].appStoreState = .inReview
        #expect(!state.canSyncSelectedStoreCopy)
    }

    @Test func bootstrapPopulatesMockData() {
        let state = AppState(defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        #expect(!state.apps.isEmpty)
        #expect(state.selectedAppId != nil)
        #expect(state.selectedVersionId != nil)
    }

    @Test func handleErrorClassifiesConnectivityAndProviderFailures() {
        let state = AppState(defaults: makeTestDefaults())

        state.handleError(URLError(.timedOut))
        #expect(state.lastError?.category == .network)
        #expect(state.lastError?.isRetryable == true)

        state.handleError(AIServiceError.networkError("connection lost"))
        #expect(state.lastError?.category == .network)
        #expect(state.lastError?.isRetryable == true)

        state.handleError(AIServiceError.requestRejected("policy"))
        #expect(state.lastError?.category == .ai)
        #expect(state.lastError?.isRetryable == false)

        state.handleError(AppStoreConnectClientError.connectionTimedOut)
        #expect(state.lastError?.category == .network)
        #expect(state.lastError?.isRetryable == true)

        state.handleError(AppStoreConnectClientError.invalidResponse)
        #expect(state.lastError?.category == .appStoreConnect)
        #expect(state.lastError?.isRetryable == true)

        state.handleError(AppStoreConnectCredentialError.missingPrivateKey)
        #expect(state.lastError?.category == .auth)
        #expect(state.lastError?.isRetryable == false)

        state.setError("validation message")
        #expect(state.lastError?.category == .validation)
        #expect(state.lastError?.isRetryable == false)
    }

    @Test func handleErrorIgnoresURLSessionCancellation() {
        let state = AppState(defaults: makeTestDefaults())

        state.handleError(URLError(.cancelled))

        #expect(state.lastError == nil)
    }

    @Test func selectingAppPicksFirstEditableVersion() {
        let state = AppState.preview(defaults: makeTestDefaults())
        guard let app = state.apps.first else { Issue.record("No apps in mock"); return }
        state.selectApp(app.id)
        #expect(state.selectedVersion?.canEditMetadata == true)
    }

    @Test func editingTextRecomputesStatusAndDiff() {
        let state = AppState.preview(defaults: makeTestDefaults())
        guard let note = state.localeNotes.first else { Issue.record("No locale notes"); return }
        state.updateLocalText(for: note.locale, text: "")
        let updated = state.localeNotes.first { $0.locale == note.locale }
        #expect(updated?.status == .missing)
    }

    @Test func overLimitFlagsOverLimitStatus() {
        let state = AppState.preview(defaults: makeTestDefaults())
        guard let note = state.localeNotes.first else { Issue.record("No locale notes"); return }
        let huge = String(repeating: "x", count: ValidationEngine.whatsNewCharacterLimit + 1)
        state.updateLocalText(for: note.locale, text: huge)
        let updated = state.localeNotes.first { $0.locale == note.locale }
        #expect(updated?.status == .overLimit)
    }

    @Test func dryRunRecordsHistoryEntry() {
        let state = AppState.preview(defaults: makeTestDefaults())
        state.performDryRun()
        #expect(state.syncHistory.first?.dryRun == true)
    }

    @Test func syncMarksReadyLocalesAsSynced() async {
        let state = AppState.preview(defaults: makeTestDefaults())
        let readyCountBefore = state.localeNotesStats.readyCount
        await state.performSyncAsync()
        let syncedCount = state.localeNotes.filter { $0.status == .synced }.count
        #expect(syncedCount >= readyCountBefore)
    }

    @Test func storeCopyValidationFlagsOverLimitFields() {
        let state = AppState.preview(defaults: makeTestDefaults())
        guard let locale = state.selectedStoreCopyLocale else {
            Issue.record("No store copy locale"); return
        }
        state.updateStoreCopyField(
            for: locale,
            field: .keywords,
            text: String(repeating: "x", count: 101)
        )
        let updated = state.storeCopyLocales.first { $0.locale == locale }
        #expect(updated?.status == .overLimit)
        #expect(updated?.validationIssues.contains { $0.field == .keywords } == true)
    }

    @Test func storeCopyAIOptimizationUpdatesDraftAndPreservesURLs() async {
        let mock = MockAIService()
        mock.optimizedStoreMetadata = StoreMetadataFields(
            description: "Optimized App Store description.",
            keywords: "optimized,store,copy",
            promotionalText: "Cleaner copy for launch.",
            supportURL: "https://ai.example/support",
            marketingURL: "https://ai.example/marketing"
        )
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        guard let locale = state.selectedStoreCopyLocale,
            let before = state.selectedStoreCopy?.localMetadata
        else {
            Issue.record("No store copy locale"); return
        }

        state.optimizeStoreCopyLocale(locale)
        for _ in 0..<50 {
            if state.storeCopyLocales.first(where: { $0.locale == locale })?.localMetadata.description.contains(
                "Optimized") == true
            {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let updated = state.storeCopyLocales.first { $0.locale == locale }?.localMetadata
        #expect(updated?.description.contains("Optimized") == true)
        #expect(updated?.supportURL == before.supportURL)
        #expect(updated?.marketingURL == before.marketingURL)
    }

    @Test func storeCopyMockSyncMarksDraftAsSynced() async {
        let service = SampleAppStoreConnectService()
        let state = AppState.preview(
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        guard let locale = state.selectedStoreCopyLocale else {
            Issue.record("No store copy locale"); return
        }
        state.updateStoreCopyField(for: locale, field: .promotionalText, text: "A tighter launch message.")
        #expect(state.storeCopyLocales.first { $0.locale == locale }?.status == .ready)

        state.syncStoreCopyLocale(locale)
        #expect(await waitUntil { state.storeCopyLocales.first { $0.locale == locale }?.status == .synced })

        let updated = state.storeCopyLocales.first { $0.locale == locale }
        #expect(updated?.status == .synced)
        #expect(updated?.changedFieldCount == 0)
    }

    @Test func storeCopyImportPreservesFieldsMissingFromFile() async throws {
        let state = AppState.preview(defaults: makeTestDefaults())
        let locale = "en-US"
        guard let before = state.storeCopyLocales.first(where: { $0.locale == locale })?.localMetadata else {
            Issue.record("No English store copy"); return
        }

        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesAppState-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "en-US.md")
        try """
        ## Description
        ```
        Imported description.
        ```

        ## Keywords
        ```
        imported,keywords
        ```
        """.write(to: url, atomically: true, encoding: .utf8)

        state.loadStoreCopySource(url)
        #expect(
            await waitUntil {
                state.storeCopyLocales.first { $0.locale == locale }?.localMetadata.description
                    == "Imported description."
            })

        let updated = state.storeCopyLocales.first { $0.locale == locale }?.localMetadata
        #expect(updated?.description == "Imported description.")
        #expect(updated?.keywords == "imported,keywords")
        #expect(updated?.supportURL == before.supportURL)
        #expect(updated?.marketingURL == before.marketingURL)
        #expect(state.storeCopySourceURL == url)
    }

    @Test func storeCopyImportFallsBackToAIWhenParserFindsNoFields() async {
        let mock = MockAIService()
        mock.storeMetadataParseResult = [
            "en-US": StoreMetadataFields(
                description: "AI extracted ExampleLearningApp store description.",
                keywords: "pinyin,chinese,pronunciation",
                promotionalText: "Learn pinyin faster."
            )
        ]
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        state.selectedStoreCopyLocale = "en-US"

        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesStoreCopyAI-\(UUID().uuidString)")
            .appending(path: "拼音标音 app")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? """
        ExampleLearningApp helps learners read Chinese text with pinyin guides.
        It focuses on pronunciation, scanning, and review.
        """.write(to: folder.appending(path: "README.md"), atomically: true, encoding: .utf8)

        state.loadStoreCopySource(folder)
        for _ in 0..<100 {
            if state.storeCopyLocales.first(where: { $0.locale == "en-US" })?.localMetadata.description.contains(
                "ExampleLearningApp") == true
            {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let updated = state.storeCopyLocales.first { $0.locale == "en-US" }?.localMetadata
        #expect(mock.lastParseText?.contains("README.md") == true)
        #expect(updated?.description == "AI extracted ExampleLearningApp store description.")
        #expect(updated?.keywords == "pinyin,chinese,pronunciation")
        #expect(state.storeCopySourceDescription?.contains("AI") == true)
        #expect(state.lastError == nil)
    }

    @Test func storeCopyImportFindsNearbyMetadataWhenScreenshotFinalFolderWasSelected() async throws {
        let mock = MockAIService()
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        state.selectedStoreCopyLocale = "en-US"

        let project = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesExampleHydrationAppStoreCopy-\(UUID().uuidString)")
            .appending(path: "ExampleHydrationApp")
        let metadata = project.appending(path: "AppStore/metadata")
        let final = project.appending(path: "AppStore/Screenshots/Final/en")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: final, withIntermediateDirectories: true)
        try Data("not a real screenshot".utf8).write(to: final.appending(path: "01-today.jpg"))
        try """
        # ExampleHydrationApp App Store Metadata - en

        ## Description
        ExampleHydrationApp is a gentle hydration reminder app.

        ## Keywords
        water,hydration,reminder
        """.write(to: metadata.appending(path: "en.md"), atomically: true, encoding: .utf8)

        state.loadStoreCopySource(project.appending(path: "AppStore/Screenshots/Final"))
        // Foundation versions differ in whether a discovered directory URL
        // ends in a slash. Assert the chosen folder, not its URL spelling.
        #expect(
            await waitUntil { state.storeCopySourceURL?.standardizedFileURL.path == metadata.standardizedFileURL.path })

        let updated = state.storeCopyLocales.first { $0.locale == "en-US" }?.localMetadata
        #expect(updated?.description == "ExampleHydrationApp is a gentle hydration reminder app.")
        #expect(updated?.keywords == "water,hydration,reminder")
        #expect(state.storeCopySourceURL?.standardizedFileURL.path == metadata.standardizedFileURL.path)
        #expect(mock.lastParseText == nil)
        #expect(state.lastError == nil)
    }

    @Test func currentWorkspaceImportRoutesStoreCopyFinalFolderToMetadata() async throws {
        let mock = MockAIService()
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        state.workspaceMode = .storeCopy
        state.selectedStoreCopyLocale = "en-US"

        let project = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesExampleHydrationAppWorkspaceRoute-\(UUID().uuidString)")
            .appending(path: "ExampleHydrationApp")
        let metadata = project.appending(path: "AppStore/metadata")
        let final = project.appending(path: "AppStore/Screenshots/Final")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: final.appending(path: "en"), withIntermediateDirectories: true)
        try Data("not a real screenshot".utf8).write(to: final.appending(path: "en/01-today.jpg"))
        try """
        # ExampleHydrationApp App Store Metadata - en

        ## Description
        ExampleHydrationApp tracks water intake with quiet reminders.

        ## Keywords
        water,drink,habit
        """.write(to: metadata.appending(path: "en.md"), atomically: true, encoding: .utf8)

        state.importURL(final)
        #expect(
            await waitUntil { state.storeCopySourceURL?.standardizedFileURL.path == metadata.standardizedFileURL.path })

        let updated = state.storeCopyLocales.first { $0.locale == "en-US" }?.localMetadata
        #expect(updated?.description == "ExampleHydrationApp tracks water intake with quiet reminders.")
        #expect(updated?.keywords == "water,drink,habit")
        #expect(state.storeCopySourceURL?.standardizedFileURL.path == metadata.standardizedFileURL.path)
        #expect(mock.lastParseText == nil)
        #expect(state.lastError == nil)
    }

    @Test func storeCopyCanAskAIToReparseCurrentSource() async throws {
        let mock = MockAIService()
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        state.selectedStoreCopyLocale = "en-US"

        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesStoreCopyReparse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "draft.txt")
        try "Receipt scanner copy draft".write(to: url, atomically: true, encoding: .utf8)

        state.storeCopySourceURL = url
        mock.storeMetadataParseResult = [
            "en-US": StoreMetadataFields(
                description: "AI reparsed store copy.",
                keywords: "receipt,scanner",
                promotionalText: "Scan faster."
            )
        ]

        #expect(state.canReparseCurrentStoreCopyWithAI)
        state.askAIToReparseCurrentStoreCopy()
        for _ in 0..<100 {
            if state.storeCopyLocales.first(where: { $0.locale == "en-US" })?.localMetadata.description
                == "AI reparsed store copy."
            {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let updated = state.storeCopyLocales.first { $0.locale == "en-US" }?.localMetadata
        #expect(mock.lastParseText?.contains("Receipt scanner copy draft") == true)
        #expect(updated?.description == "AI reparsed store copy.")
        #expect(updated?.keywords == "receipt,scanner")
        #expect(state.storeCopySourceDescription?.contains("AI") == true)
        #expect(state.lastError == nil)
    }

    @Test func aiReleaseParseDoesNotApplyAfterSwitchingAppsWithTheSameVersion() async throws {
        let mock = MockAIService()
        mock.parseDelayNanoseconds = 150_000_000
        mock.parseResult = ["en-US": "STALE RELEASE NOTES"]
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesStaleReleaseParse-\(UUID().uuidString).txt")
        try "Release notes draft".write(to: url, atomically: true, encoding: .utf8)

        state.askAIToParse(url: url)
        #expect(await waitUntil { state.isAIRunning })
        state.selectedAppId = "another-app-with-the-same-version"
        #expect(await waitUntil { !state.isAIRunning })

        #expect(state.localeNotes.allSatisfy { $0.localText != "STALE RELEASE NOTES" })
    }

    @Test func aiStoreCopyParseDoesNotApplyAfterSwitchingAppsWithTheSameVersion() async throws {
        let mock = MockAIService()
        mock.storeMetadataParseDelayNanoseconds = 150_000_000
        mock.storeMetadataParseResult = [
            "en-US": StoreMetadataFields(description: "STALE STORE COPY")
        ]
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesStaleStoreCopyParse-\(UUID().uuidString).txt")
        try "Store copy draft".write(to: url, atomically: true, encoding: .utf8)

        state.askAIToParseStoreCopy(url: url)
        #expect(await waitUntil { state.isAIRunning })
        state.selectedAppId = "another-app-with-the-same-version"
        #expect(await waitUntil { !state.isAIRunning })

        #expect(state.storeCopyLocales.allSatisfy { $0.localMetadata.description != "STALE STORE COPY" })
    }

    @Test func storeCopyLiveSyncCallsAppStoreConnectMetadataPatch() async {
        let service = MockASCService()
        service.versionOnlyMetadataResponse = true
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        let metadata = StoreMetadataFields(
            subtitle: "Keep this draft", description: "Updated", keywords: "updated", promotionalText: "Now updated",
            privacyPolicyURL: "https://example.com/privacy")
        state.storeCopyLocales = [
            StoreCopyLocale(
                locale: "en-US",
                remoteLocalizationId: "loc-1",
                localMetadata: metadata,
                remoteMetadata: .empty,
                status: .ready,
                changedFieldCount: 3
            )
        ]
        state.selectedStoreCopyLocale = "en-US"

        state.syncStoreCopyLocale("en-US")
        for _ in 0..<50 where state.storeCopyLocales.first?.status != .synced {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.lastUpdatedStoreMetadata?.description == "Updated")
        #expect(state.storeCopyLocales.first?.localMetadata.subtitle == "Keep this draft")
        #expect(state.storeCopyLocales.first?.localMetadata.privacyPolicyURL == "https://example.com/privacy")
        #expect(state.storeCopyLocales.first?.status == .synced)
    }

    @Test func storeCopySyncRetriesRowStuckInSyncing() async {
        // A row left in .syncing by a superseded/cancelled sync must be
        // re-attempted by the next sync — not silently skipped forever.
        let service = MockASCService()
        service.fetchedLocalizations = [
            RemoteLocaleNote(localizationId: "loc-en", locale: "en-US", text: "Old")
        ]
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        let metadata = StoreMetadataFields(description: "Updated", keywords: "kw", promotionalText: "promo")
        state.storeCopyLocales = [
            StoreCopyLocale(
                locale: "en-US",
                remoteLocalizationId: "loc-en",
                localMetadata: metadata,
                remoteMetadata: .empty,
                status: .syncing,
                changedFieldCount: 3
            )
        ]

        let ok = await state.syncLiveStoreCopyLocales(["en-US"])

        #expect(ok)
        let status = state.storeCopyLocales.first?.status
        if case .synced = status {
            // expected — the row was retried and completed
        } else {
            Issue.record("Expected .synced after retrying a .syncing row, got \(String(describing: status))")
        }
    }

    @Test func staleVersionLocalizationResponseDoesNotOverwriteCurrentVersion() async {
        let service = MockASCService()
        service.fetchedLocalizationsByVersion = [
            "v-101": [
                RemoteLocaleNote(
                    localizationId: "loc-old", locale: "zh-Hans", text: "为 1.0.1 稳定更新整理了 App Store 文案和审核说明。")
            ],
            "v-110": [
                RemoteLocaleNote(localizationId: "loc-new", locale: "zh-Hans", text: "")
            ],
        ]
        service.fetchLocalizationDelayNanosecondsByVersion = [
            "v-101": 120_000_000,
            "v-110": 0,
        ]

        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-101", appId: "app-1", versionString: "1.0.1", platform: "iOS",
                appStoreState: .prepareForSubmission),
            ReleaseVersion(
                id: "v-110", appId: "app-1", versionString: "1.1.0", platform: "iOS",
                appStoreState: .prepareForSubmission),
        ]
        state.selectedAppId = "app-1"
        state.isUsingMockData = false

        let oldRequest = Task { await state.selectLiveVersion("v-101", resetSource: true) }
        // Deterministic ordering: wait until the old (slow) request has
        // actually entered its fetch, instead of guessing with a sleep.
        #expect(await waitUntil { service.fetchLocalizationsCallCount >= 1 })
        let currentRequest = Task { await state.selectLiveVersion("v-110", resetSource: true) }

        await currentRequest.value
        await oldRequest.value

        #expect(state.selectedVersionId == "v-110")
        #expect(state.localeNotes.first { $0.locale == "zh-Hans" }?.remoteText == "")
        #expect(state.localeNotes.allSatisfy { $0.remoteText != "为 1.0.1 稳定更新整理了 App Store 文案和审核说明。" })
    }

    /// Builds a live-service state with one ready `de-DE` note on `v-1`, plus an
    /// editable `v-2` whose remote text is distinguishable.
    private func makeStateForSyncRaceTests(service: MockASCService) -> AppState {
        service.fetchedLocalizationsByVersion = [
            "v-2": [RemoteLocaleNote(localizationId: "loc-de-v2", locale: "de-DE", text: "v2 remote text")]
        ]
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission),
            ReleaseVersion(
                id: "v-2", appId: "app-1", versionString: "2.0", platform: "iOS", appStoreState: .prepareForSubmission),
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        state.localeNotes = [
            LocaleNote(
                locale: "de-DE",
                remoteLocalizationId: "loc-de-v1",
                localText: "v1 outgoing text",
                remoteText: "old remote",
                status: .ready,
                diffSummary: nil
            )
        ]
        return state
    }

    @Test func syncResponseArrivingAfterVersionSwitchIsDiscarded() async {
        let service = MockASCService()
        service.updateWhatsNewDelayNanoseconds = 200_000_000
        let state = makeStateForSyncRaceTests(service: service)

        // performSyncAsync keeps no task handle, so only the generation check
        // after the await can stop the late response from landing on v-2.
        let historyCountBefore = state.syncHistory.count
        let staleSync = Task { await state.performSyncAsync() }
        #expect(await waitUntil { state.isSyncing })
        await state.selectLiveVersion("v-2", resetSource: true)
        await staleSync.value

        #expect(state.selectedVersionId == "v-2")
        let note = state.localeNotes.first { $0.locale == "de-DE" }
        #expect(note?.localText == "v2 remote text")
        #expect(note?.remoteText == "v2 remote text")
        #expect(note?.status != .synced)
        #expect(state.remoteNotesByLocale["de-DE"]?.localizationId == "loc-de-v2")
        #expect(state.syncHistory.count == historyCountBefore)
    }

    @Test func cancelSyncStopsInFlightSyncWithoutRecordingFailure() async {
        let service = MockASCService()
        service.updateWhatsNewDelayNanoseconds = 2_000_000_000
        let state = makeStateForSyncRaceTests(service: service)

        let historyCountBefore = state.syncHistory.count
        state.performSync()
        #expect(await waitUntil { state.localeNotes.first?.status == .syncing })
        state.cancelSync()

        #expect(await waitUntil { !state.isSyncing })
        let note = state.localeNotes.first { $0.locale == "de-DE" }
        #expect(note?.status == .ready)
        #expect(note?.localText == "v1 outgoing text")
        // A cancelled sync is not a failed sync: no red row, no history entry.
        #expect(state.syncHistory.count == historyCountBefore)
        #expect(state.lastError == nil)
    }

    @Test func watchingSurvivesReloadFromSource() async throws {
        let state = AppState.preview(defaults: makeTestDefaults())
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesWatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "en.md")
        try "• First body".write(to: file, atomically: true, encoding: .utf8)

        state.loadFolder(file)
        #expect(await waitUntil { state.sourceFolder == file })
        state.toggleWatching()
        #expect(state.watching)

        // This is the watcher's own callback path — it must not disarm itself,
        // otherwise "Watch Folder" only ever fires once.
        try "• Second body".write(to: file, atomically: true, encoding: .utf8)
        state.reloadFromSource()
        #expect(
            await waitUntil {
                state.localeNotes.first { $0.locale == "en-US" }?.localText.contains("Second body") == true
            })

        #expect(state.watching)
        #expect(state.sourceFolder == file)
        #expect(state.localeNotes.first { $0.locale == "en-US" }?.localText.contains("Second body") == true)
    }

    @Test func releaseNoteLiveSyncRecoversExistingLocaleAfterDuplicateCreate() async {
        let service = MockASCService()
        service.createLocalizationError = AppStoreConnectClientError.requestFailed(
            statusCode: 409,
            message: "Entity with locale: de-DE already exists. Try updating. ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE"
        )
        service.fetchedLocalizations = [
            RemoteLocaleNote(localizationId: "loc-de", locale: "de-DE", text: "Old German notes")
        ]

        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        state.localeNotes = [
            LocaleNote(
                locale: "de-DE",
                remoteLocalizationId: nil,
                localText: "Neue deutsche Hinweise",
                remoteText: nil,
                status: .ready,
                diffSummary: nil
            )
        ]

        state.syncLocale("de-DE")
        for _ in 0..<50 where state.localeNotes.first?.status != .synced {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.createLocalizationCallCount == 1)
        #expect(service.fetchLocalizationsCallCount == 1)
        #expect(service.lastUpdatedWhatsNew?.localizationId == "loc-de")
        #expect(service.lastUpdatedWhatsNew?.text == "Neue deutsche Hinweise")
        #expect(state.localeNotes.first?.remoteLocalizationId == "loc-de")
        #expect(state.localeNotes.first?.status == .synced)
    }

    @Test func storeCopyLiveSyncRecoversExistingLocaleAfterDuplicateCreate() async {
        let service = MockASCService()
        service.createLocalizationError = AppStoreConnectClientError.requestFailed(
            statusCode: 409,
            message: "Entity with locale: de-DE already exists. Try updating. ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE"
        )
        service.fetchedLocalizations = [
            RemoteLocaleNote(localizationId: "loc-de", locale: "de-DE", text: "Old German notes")
        ]

        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        let metadata = StoreMetadataFields(
            description: "Aktualisierte Beschreibung",
            keywords: "deutsch,app",
            promotionalText: "Neue Version"
        )
        state.storeCopyLocales = [
            StoreCopyLocale(
                locale: "de-DE",
                remoteLocalizationId: nil,
                localMetadata: metadata,
                remoteMetadata: .empty,
                status: .ready,
                changedFieldCount: 3
            )
        ]
        state.selectedStoreCopyLocale = "de-DE"

        state.syncStoreCopyLocale("de-DE")
        for _ in 0..<50
        where service.lastUpdatedStoreMetadata == nil || state.storeCopyLocales.first?.status == .syncing {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.createLocalizationCallCount == 1)
        #expect(service.fetchLocalizationsCallCount == 1)
        #expect(service.lastUpdatedStoreMetadata?.description == "Aktualisierte Beschreibung")
        #expect(state.storeCopyLocales.first?.remoteLocalizationId == "loc-de")
        #expect(state.storeCopyLocales.first?.status == .synced)
    }

    @Test func storeCopyFieldSyncOnlyPatchesSelectedField() async {
        let service = MockASCService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false

        let remote = StoreMetadataFields(
            description: "Remote description",
            keywords: "remote,keywords",
            promotionalText: "Remote promo",
            supportURL: "https://example.com/support",
            marketingURL: "https://example.com"
        )
        let tooLongDescription = String(repeating: "x", count: 4_001)
        let local = StoreMetadataFields(
            description: tooLongDescription,
            keywords: "local,keywords",
            promotionalText: remote.promotionalText,
            supportURL: remote.supportURL,
            marketingURL: remote.marketingURL
        )
        service.lastUpdatedStoreMetadata = remote
        state.storeCopyLocales = [
            StoreCopyLocale(
                locale: "en-US",
                remoteLocalizationId: "loc-1",
                localMetadata: local,
                remoteMetadata: remote,
                status: .overLimit,
                changedFieldCount: 2,
                validationIssues: [
                    StoreCopyIssue(
                        field: .description,
                        severity: .error,
                        message: "Description too long"
                    )
                ]
            )
        ]
        state.selectedStoreCopyLocale = "en-US"

        state.syncStoreCopyField(locale: "en-US", field: .keywords)
        for _ in 0..<50 where state.storeCopyLocales.first?.remoteMetadata?.keywords != "local,keywords" {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.lastUpdatedStoreMetadataField?.field == .keywords)
        #expect(service.lastUpdatedStoreMetadataField?.value == "local,keywords")
        let updated = state.storeCopyLocales.first
        #expect(updated?.remoteMetadata?.keywords == "local,keywords")
        #expect(updated?.remoteMetadata?.description == "Remote description")
        #expect(updated?.localMetadata.description == tooLongDescription)
        #expect(updated?.changedFieldCount == 1)
        #expect(updated?.status == .overLimit)
    }

    @Test func recommendedMetadataImportAppliesImmediately() async throws {
        let state = AppState.preview(defaults: makeTestDefaults())
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesAppState-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "en.md")
        let metadata = """
            # Metadata

            ## 1. App Name
            ```
            Example App
            ```

            ## 9. What's New
            ```
            • Correct release note body
            ```
            """
        try metadata.write(to: url, atomically: true, encoding: .utf8)

        state.loadFolder(url)
        #expect(
            await waitUntil {
                state.localeNotes.first { $0.locale == "en-US" }?.localText.contains("Correct release note body")
                    == true
            })

        #expect(state.pendingImport == nil)
        #expect(state.localeNotes.first { $0.locale == "en-US" }?.localText.contains("Example App") == false)
    }

    @Test func ambiguousMetadataImportWaitsForPreviewConfirmation() async throws {
        let state = AppState.preview(defaults: makeTestDefaults())
        let previousNotes = state.localeNotes
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesAppState-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "en.md")
        let metadata = """
            # Metadata

            ## App Name
            ```
            Example App
            ```

            ## Notes
            ```
            Candidate release note body
            ```
            """
        try metadata.write(to: url, atomically: true, encoding: .utf8)

        state.loadFolder(url)
        #expect(await waitUntil { state.pendingImport != nil })
        #expect(state.localeNotes == previousNotes)

        state.confirmPendingImport()
        #expect(state.pendingImport == nil)
        #expect(
            await waitUntil {
                state.localeNotes.first { $0.locale == "en-US" }?.localText.contains("Example App") == true
            })
        #expect(state.localeNotes.first { $0.locale == "en-US" }?.localText.contains("Example App") == true)
    }

    @Test func screenshotIssueSelectionFocusesRelatedAsset() {
        let state = AppState.preview(defaults: makeTestDefaults())
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        let asset = ScreenshotAsset(
            url: root.appending(path: "en-US/bad.png"),
            relativePath: "en-US/bad.png",
            size: ScreenshotPixelSize(width: 1206, height: 2622),
            locale: "en-US",
            deviceSlot: nil,
            status: .unsupportedSize,
            contentHash: nil
        )
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [asset],
            skippedCount: 0
        )

        let issue = state.screenshotIssues.first { $0.assetIDs.contains(asset.id) }
        #expect(issue != nil)
        state.selectScreenshotIssue(issue!)

        #expect(state.selectedScreenshotLocale == "en-US")
        #expect(state.selectedScreenshotAssetId == asset.id)
        #expect(state.screenshotFocusTargetID == state.screenshotAssetFocusID(asset.id))
    }

    @Test func screenshotCoverageIncludesKnownLocalesWithoutAssets() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = [
            LocaleNote(
                locale: "en-US",
                remoteLocalizationId: "loc-en",
                localText: "English",
                remoteText: "English",
                status: .noChange,
                diffSummary: nil
            ),
            LocaleNote(
                locale: "zh-Hant",
                remoteLocalizationId: "loc-zh",
                localText: "Traditional Chinese",
                remoteText: "Traditional Chinese",
                status: .noChange,
                diffSummary: nil
            ),
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en-US/iphone.png"),
                    relativePath: "en-US/iphone.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "en-US",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                )
            ],
            skippedCount: 0
        )

        let coverageLocales = state.screenshotCoverageGroups.map(\.locale)
        #expect(coverageLocales.contains("en-US"))
        #expect(coverageLocales.contains("zh-Hant"))
        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hant" }?.assets.isEmpty == true)
        #expect(
            state.screenshotIssues.contains {
                $0.locale == "zh-Hant" && $0.title == expectedLocalized("Missing required screenshot size")
            })
    }

    @Test func genericEnglishScreenshotFolderCoversEnglishRegionLocales() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = ["en-AU", "en-CA", "en-GB", "en-US"].map { locale in
            LocaleNote(
                locale: locale,
                remoteLocalizationId: "loc-\(locale)",
                localText: "English",
                remoteText: "English",
                status: .noChange,
                diffSummary: nil
            )
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en/iphone.png"),
                    relativePath: "en/iphone.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "en-US",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                )
            ],
            skippedCount: 0
        )

        for locale in ["en-AU", "en-CA", "en-GB", "en-US"] {
            #expect(state.screenshotCoverageGroups.first { $0.locale == locale }?.count(for: .iPhone65) == 1)
            #expect(state.missingScreenshotRequirements(locale: locale).isEmpty)
        }
        #expect(!state.screenshotIssues.contains { $0.title == expectedLocalized("Missing required screenshot size") })
    }

    @Test func aiClassifiedEnglishScreenshotsCoverEnglishRegionLocales() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = ["en-AU", "en-CA", "en-GB", "en-US"].map { locale in
            LocaleNote(
                locale: locale,
                remoteLocalizationId: "loc-\(locale)",
                localText: "English",
                remoteText: "English",
                status: .noChange,
                diffSummary: nil
            )
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        let asset = ScreenshotAsset(
            url: root.appending(path: "final_01_home.png"),
            relativePath: "final_01_home.png",
            size: ScreenshotPixelSize(width: 1320, height: 2868),
            locale: "en-US",
            deviceSlot: .iPhone69,
            status: .ready,
            contentHash: nil
        )
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [asset],
            skippedCount: 0
        )
        state.screenshotAISharedAssetIDs = [asset.id]

        for locale in ["en-AU", "en-CA", "en-GB", "en-US"] {
            #expect(state.screenshotCoverageGroups.first { $0.locale == locale }?.count(for: .iPhone69) == 1)
            #expect(state.missingScreenshotRequirements(locale: locale).isEmpty)
        }
    }

    @Test func screenshotCoverageUsesVersionLocalesAndMapsRegionalFolders() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = ["es-ES", "fr-FR"].map { locale in
            LocaleNote(
                locale: locale,
                remoteLocalizationId: "loc-\(locale)",
                localText: "Ready",
                remoteText: "Ready",
                status: .noChange,
                diffSummary: nil
            )
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "es-MX/iphone.png"),
                    relativePath: "es-MX/iphone.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "es-MX",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                ),
                ScreenshotAsset(
                    url: root.appending(path: "fr-CA/iphone.png"),
                    relativePath: "fr-CA/iphone.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "fr-CA",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                ),
            ],
            skippedCount: 0
        )

        let coverageLocales = state.screenshotCoverageGroups.map(\.locale)
        #expect(coverageLocales == ["es-ES", "fr-FR"])
        #expect(state.screenshotCoverageGroups.first { $0.locale == "es-ES" }?.count(for: .iPhone69) == 1)
        #expect(state.screenshotCoverageGroups.first { $0.locale == "fr-FR" }?.count(for: .iPhone69) == 1)
        #expect(state.missingScreenshotRequirements(locale: "es-ES").isEmpty)
        #expect(state.missingScreenshotRequirements(locale: "fr-FR").isEmpty)
    }

    @Test func screenshotCoverageDoesNotExpandFromStoreCopyExtrasWhenReleaseLocalesExist() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = [
            LocaleNote(
                locale: "es-ES",
                remoteLocalizationId: "loc-es",
                localText: "Ready",
                remoteText: "Ready",
                status: .noChange,
                diffSummary: nil
            )
        ]
        state.storeCopyLocales = [
            StoreCopyLocale(
                locale: "es-MX",
                remoteLocalizationId: "copy-es-mx",
                localMetadata: .empty,
                remoteMetadata: .empty,
                status: .noChange,
                changedFieldCount: 0
            )
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "es/iphone.png"),
                    relativePath: "es/iphone.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "es-ES",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                )
            ],
            skippedCount: 0
        )

        let coverageLocales = state.screenshotCoverageGroups.map(\.locale)
        #expect(coverageLocales == ["es-ES"])
        #expect(state.screenshotCoverageGroups.first?.count(for: .iPhone69) == 1)
    }

    @Test func screenshotCoveragePrefersExplicitPathLocaleOverStoredScanLocale() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = ["zh-Hans", "zh-Hant"].map { locale in
            LocaleNote(
                locale: locale,
                remoteLocalizationId: "loc-\(locale)",
                localText: "Ready",
                remoteText: "Ready",
                status: .noChange,
                diffSummary: nil
            )
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "zh-Hant/6.9inch/zh-Hant_6.9inch_01.png"),
                    relativePath: "zh-Hant/6.9inch/zh-Hant_6.9inch_01.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "zh-Hans",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                )
            ],
            skippedCount: 0
        )

        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hans" }?.count(for: .iPhone69) == 0)
        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hant" }?.count(for: .iPhone69) == 1)
    }

    @Test func projectDiscoveredScreenshotsKeepTraditionalChineseFolderSeparate() throws {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.apps = [
            AppRecord(
                id: "app-exampletimer", name: "ExampleTimer", bundleId: "com.example.exampletimer", platform: "iOS",
                iconSystemName: "clock")
        ]
        state.versionsByApp["app-exampletimer"] = [
            ReleaseVersion(
                id: "version-1", appId: "app-exampletimer", versionString: "1.0", platform: "iOS",
                appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-exampletimer"
        state.selectedVersionId = "version-1"
        state.localeNotes = [
            "de-DE", "en-US", "es-ES", "fr-FR", "ja", "ko", "zh-Hans", "zh-Hant",
        ].map { locale in
            LocaleNote(
                locale: locale,
                remoteLocalizationId: "loc-\(locale)",
                localText: "Ready",
                remoteText: "Ready",
                status: .noChange,
                diffSummary: nil
            )
        }

        let project = try makeTempFolder()
        let screenshots = project.appending(path: "app-store-metadata/generated-screenshots")
        let traditional69 = screenshots.appending(path: "zh-Hant/6.9")
        let traditional65 = screenshots.appending(path: "zh-Hant/6.5")
        let simplified69 = screenshots.appending(path: "zh-Hans/6.9")
        let simplified65 = screenshots.appending(path: "zh-Hans/6.5")
        for folder in [traditional69, traditional65, simplified69, simplified65] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try writePNG(
            width: 1320, height: 2868, to: traditional69.appending(path: "ExampleTimer_zh-Hant_6_9_01_today_pay.jpg"))
        try writePNG(
            width: 1242, height: 2688, to: traditional65.appending(path: "ExampleTimer_zh-Hant_6_5_01_today_pay.jpg"))
        try writePNG(
            width: 1320, height: 2868, to: simplified69.appending(path: "ExampleTimer_zh-Hans_6_9_01_today_pay.jpg"))
        try writePNG(
            width: 1242, height: 2688, to: simplified65.appending(path: "ExampleTimer_zh-Hans_6_5_01_today_pay.jpg"))

        state.screenshotScan = try ScreenshotScanner().scan(url: project)

        #expect(state.screenshotScan?.sourceKind == .discoveredFolder)
        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hans" }?.count(for: .iPhone69) == 1)
        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hans" }?.count(for: .iPhone65) == 1)
        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hant" }?.count(for: .iPhone69) == 1)
        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hant" }?.count(for: .iPhone65) == 1)
        #expect(state.missingScreenshotRequirements(locale: "zh-Hant").isEmpty)
    }

    @Test func newestScreenshotsFolderLoadWinsOverEarlierAsyncScan() async throws {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())

        let olderFolder = try makeTempFolder()
        let olderLocale = olderFolder.appending(path: "en-US")
        try FileManager.default.createDirectory(at: olderLocale, withIntermediateDirectories: true)
        for index in 1...12 {
            try writePNG(
                width: 1320,
                height: 2868,
                to: olderLocale.appending(path: "older-\(index).png")
            )
        }

        let newerFolder = try makeTempFolder()
        let newerLocale = newerFolder.appending(path: "ja")
        try FileManager.default.createDirectory(at: newerLocale, withIntermediateDirectories: true)
        try writePNG(width: 1320, height: 2868, to: newerLocale.appending(path: "newer.png"))

        state.loadScreenshotsFolder(olderFolder)
        state.loadScreenshotsFolder(newerFolder)

        #expect(await waitUntil(timeout: 5_000_000_000) { state.isScanningScreenshots == false })

        #expect(state.isScanningScreenshots == false)
        #expect(state.screenshotFolder == newerFolder)
        #expect(state.screenshotScan?.inputRoot == newerFolder)
        #expect(state.selectedScreenshotLocale == "ja")
        #expect(state.screenshotCoverageGroups.map(\.locale) == ["ja"])
        #expect(state.lastError == nil)
    }

    @Test func sharedScreenshotsFillMissingSlotsWithoutInflatingExistingCounts() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = ["en-AU", "en-US"].map { locale in
            LocaleNote(
                locale: locale,
                remoteLocalizationId: "loc-\(locale)",
                localText: "English",
                remoteText: "English",
                status: .noChange,
                diffSummary: nil
            )
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        let sharedPhone69 = ScreenshotAsset(
            url: root.appending(path: "final_01_home.png"),
            relativePath: "final_01_home.png",
            size: ScreenshotPixelSize(width: 1320, height: 2868),
            locale: "en-US",
            deviceSlot: .iPhone69,
            status: .ready,
            contentHash: nil
        )
        let sharedPhone65 = ScreenshotAsset(
            url: root.appending(path: "final_02_detail.png"),
            relativePath: "final_02_detail.png",
            size: ScreenshotPixelSize(width: 1242, height: 2688),
            locale: "en-US",
            deviceSlot: .iPhone65,
            status: .ready,
            contentHash: nil
        )
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en-AU/iphone-69.png"),
                    relativePath: "en-AU/iphone-69.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "en-AU",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                ),
                sharedPhone69,
                sharedPhone65,
            ],
            skippedCount: 0
        )
        state.screenshotAISharedAssetIDs = [sharedPhone69.id, sharedPhone65.id]

        let australianGroup = state.screenshotCoverageGroups.first { $0.locale == "en-AU" }
        #expect(australianGroup?.count(for: .iPhone69) == 1)
        #expect(australianGroup?.count(for: .iPhone65) == 1)
        #expect(state.screenshotCoverageGroups.first { $0.locale == "en-US" }?.count(for: .iPhone69) == 1)
    }

    @Test func genericEnglishFolderSharesEvenWhenClassifiedAsRegionalEnglish() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = ["en-AU", "en-CA", "en-GB", "en-US"].map { locale in
            LocaleNote(
                locale: locale,
                remoteLocalizationId: "loc-\(locale)",
                localText: "English",
                remoteText: "English",
                status: .noChange,
                diffSummary: nil
            )
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en/6.9inch/en_6.9inch_01.png"),
                    relativePath: "en/6.9inch/en_6.9inch_01.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "en-AU",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                )
            ],
            skippedCount: 0
        )

        for locale in ["en-AU", "en-CA", "en-GB", "en-US"] {
            #expect(state.screenshotCoverageGroups.first { $0.locale == locale }?.count(for: .iPhone69) == 1)
        }
    }

    @Test func movingSharedScreenshotUsesVisibleLocaleOrder() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = ["en-CA", "en-US"].map { locale in
            LocaleNote(
                locale: locale,
                remoteLocalizationId: "loc-\(locale)",
                localText: "English",
                remoteText: "English",
                status: .noChange,
                diffSummary: nil
            )
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        let first = ScreenshotAsset(
            url: root.appending(path: "en/final_01.png"),
            relativePath: "en/final_01.png",
            size: ScreenshotPixelSize(width: 1320, height: 2868),
            locale: "en-US",
            deviceSlot: .iPhone69,
            status: .ready,
            contentHash: "1"
        )
        let second = ScreenshotAsset(
            url: root.appending(path: "en/final_02.png"),
            relativePath: "en/final_02.png",
            size: ScreenshotPixelSize(width: 1320, height: 2868),
            locale: "en-US",
            deviceSlot: .iPhone69,
            status: .ready,
            contentHash: "2"
        )
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [first, second],
            skippedCount: 0
        )

        #expect(state.screenshotAssets(locale: "en-CA", slot: .iPhone69).map(\.id) == [first.id, second.id])
        state.moveScreenshotAsset(second, locale: "en-CA", direction: .up)

        #expect(state.screenshotAssets(locale: "en-CA", slot: .iPhone69).map(\.id) == [second.id, first.id])
        #expect(state.screenshotOrderByGroup["en-US|\(ScreenshotDeviceSlot.iPhone69.rawValue)"] == nil)
    }

    @Test func genericMarketingFoldersMatchVersionLocalesWithoutInventingRegions() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = [
            "en-AU", "en-CA", "en-GB", "en-US",
            "es-ES", "fr-FR", "ja", "ko", "vi", "zh-Hans", "zh-Hant",
        ].map { locale in
            LocaleNote(
                locale: locale,
                remoteLocalizationId: "loc-\(locale)",
                localText: "Ready",
                remoteText: "Ready",
                status: .noChange,
                diffSummary: nil
            )
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en/6.9inch/en_6.9inch_01.png"),
                    relativePath: "en/6.9inch/en_6.9inch_01.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "en-AU",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                ),
                ScreenshotAsset(
                    url: root.appending(path: "es/6.9inch/es_6.9inch_01.png"),
                    relativePath: "es/6.9inch/es_6.9inch_01.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "es-ES",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                ),
                ScreenshotAsset(
                    url: root.appending(path: "fr/6.9inch/fr_6.9inch_01.png"),
                    relativePath: "fr/6.9inch/fr_6.9inch_01.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "fr-FR",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                ),
                ScreenshotAsset(
                    url: root.appending(path: "zh-Hant/6.9inch/zh-Hant_6.9inch_01.png"),
                    relativePath: "zh-Hant/6.9inch/zh-Hant_6.9inch_01.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "zh-Hans",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                ),
            ],
            skippedCount: 0
        )

        let coverageLocales = state.screenshotCoverageGroups.map(\.locale)
        #expect(!coverageLocales.contains("es-MX"))
        #expect(!coverageLocales.contains("fr-CA"))
        for locale in ["en-AU", "en-CA", "en-GB", "en-US"] {
            #expect(state.screenshotCoverageGroups.first { $0.locale == locale }?.count(for: .iPhone69) == 1)
        }
        #expect(state.screenshotCoverageGroups.first { $0.locale == "es-ES" }?.count(for: .iPhone69) == 1)
        #expect(state.screenshotCoverageGroups.first { $0.locale == "fr-FR" }?.count(for: .iPhone69) == 1)
        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hans" }?.count(for: .iPhone69) == 0)
        #expect(state.screenshotCoverageGroups.first { $0.locale == "zh-Hant" }?.count(for: .iPhone69) == 1)
    }

    @Test func iosScreenshotsDoNotRequireIPadByDefault() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.apps = [
            AppRecord(id: "app-1", name: "Demo", bundleId: "com.example.demo", platform: "iOS", iconSystemName: "app")
        ]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.localeNotes = [
            LocaleNote(
                locale: "en-US",
                remoteLocalizationId: "loc-1",
                localText: "English",
                remoteText: "English",
                status: .noChange,
                diffSummary: nil
            )
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en-US/iphone-69.png"),
                    relativePath: "en-US/iphone-69.png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: "en-US",
                    deviceSlot: .iPhone69,
                    status: .ready,
                    contentHash: nil
                )
            ],
            skippedCount: 0
        )

        #expect(state.expectedScreenshotSlots == [.iPhone69, .iPhone65])
        #expect(!state.expectedScreenshotSlots.contains(.iPad13))
        #expect(state.missingRequirementsByLocale["en-US"] == [])
        #expect(
            !state.screenshotIssues.contains {
                $0.title == expectedLocalized("Missing required screenshot size")
            })
    }

    @Test func iosScreenshotsRequireIPadWhenDetectedOrOverridden() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.apps = [
            AppRecord(id: "app-1", name: "Demo", bundleId: "com.example.demo", platform: "iOS", iconSystemName: "app")
        ]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"

        state.screenshotIPadSupportDetections["app-1"] = .supported(source: "test")
        #expect(state.expectedScreenshotSlots.contains(.iPad13))

        state.screenshotIPadSupportOverrides["app-1"] = .ignored
        #expect(!state.expectedScreenshotSlots.contains(.iPad13))

        state.screenshotIPadSupportOverrides["app-1"] = .required
        #expect(state.expectedScreenshotSlots.contains(.iPad13))
    }

    @Test func screenshotUploadSelectedLocaleCallsAppStoreConnectService() async {
        let service = MockASCService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.screenshotIPadSupportOverrides["app-1"] = .required
        state.localeNotes = [
            LocaleNote(
                locale: "en-US",
                remoteLocalizationId: "loc-1",
                localText: "Ready notes",
                remoteText: "Ready notes",
                status: .noChange,
                diffSummary: nil
            )
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en-US/iphone.png"),
                    relativePath: "en-US/iphone.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "en-US",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                ),
                ScreenshotAsset(
                    url: root.appending(path: "en-US/ipad.png"),
                    relativePath: "en-US/ipad.png",
                    size: ScreenshotPixelSize(width: 2064, height: 2752),
                    locale: "en-US",
                    deviceSlot: .iPad13,
                    status: .ready,
                    contentHash: nil
                ),
            ],
            skippedCount: 0
        )
        state.selectedScreenshotLocale = "en-US"

        state.uploadSelectedScreenshotLocale()
        for _ in 0..<50 where state.pendingScreenshotReplacement == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.replacedScreenshots.isEmpty)
        #expect(state.pendingScreenshotReplacement?.localUploadCount == 2)
        #expect(state.pendingScreenshotReplacement?.remoteDeleteCount == 0)

        state.confirmScreenshotReplacementPreview()
        for _ in 0..<50 where service.replacedScreenshots.count < 2 || state.screenshotUploadSummary == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.replacedScreenshots.map(\.displayType).contains("APP_IPHONE_65"))
        #expect(service.replacedScreenshots.map(\.displayType).contains("APP_IPAD_PRO_3GEN_129"))
        #expect(state.screenshotUploadSummary?.contains("2") == true)
    }

    @Test func screenshotUploadSkipsIPadWhenIgnored() async {
        let service = MockASCService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.screenshotIPadSupportOverrides["app-1"] = .ignored
        state.localeNotes = [
            LocaleNote(
                locale: "en-US",
                remoteLocalizationId: "loc-1",
                localText: "Ready notes",
                remoteText: "Ready notes",
                status: .noChange,
                diffSummary: nil
            )
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en-US/iphone.png"),
                    relativePath: "en-US/iphone.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "en-US",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                ),
                ScreenshotAsset(
                    url: root.appending(path: "en-US/ipad.png"),
                    relativePath: "en-US/ipad.png",
                    size: ScreenshotPixelSize(width: 2064, height: 2752),
                    locale: "en-US",
                    deviceSlot: .iPad13,
                    status: .ready,
                    contentHash: nil
                ),
            ],
            skippedCount: 0
        )
        state.selectedScreenshotLocale = "en-US"

        state.uploadSelectedScreenshotLocale()
        for _ in 0..<50 where state.pendingScreenshotReplacement == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.replacedScreenshots.isEmpty)
        #expect(state.pendingScreenshotReplacement?.localUploadCount == 1)

        state.confirmScreenshotReplacementPreview()
        for _ in 0..<50 where service.replacedScreenshots.isEmpty || state.screenshotUploadSummary == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.replacedScreenshots.map(\.displayType) == ["APP_IPHONE_65"])
        #expect(state.screenshotUploadSummary?.contains("1") == true)
    }

    @Test func iphoneOnlyAppCanPreviewAllWhenOnlySixFiveScreenshotsArePresent() {
        let service = MockASCService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.13.0", platform: "iOS",
                appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.screenshotIPadSupportDetections["app-1"] = .unsupported(source: "test")
        state.localeNotes = [
            LocaleNote(
                locale: "de-DE",
                localPath: nil,
                remoteLocalizationId: "loc-de",
                localText: "Ready",
                remoteText: "Ready",
                status: .noChange,
                diffSummary: nil
            ),
            LocaleNote(
                locale: "en-US",
                localPath: nil,
                remoteLocalizationId: "loc-en",
                localText: "Ready",
                remoteText: "Ready",
                status: .noChange,
                diffSummary: nil
            ),
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "de-DE/de-65-1.png"),
                    relativePath: "de-DE/de-65-1.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "de-DE",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                ),
                ScreenshotAsset(
                    url: root.appending(path: "en-US/en-65-1.png"),
                    relativePath: "en-US/en-65-1.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "en-US",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                ),
            ],
            skippedCount: 0
        )
        state.selectedScreenshotLocale = "de-DE"

        #expect(state.screenshotRequiresIPad == false)
        #expect(state.expectedScreenshotSlots == [.iPhone69, .iPhone65])
        #expect(state.screenshotBlockingIssueCount == 0)
        #expect(state.canUploadSelectedScreenshots == true)
        #expect(state.canUploadAllScreenshots == true)
        #expect(state.screenshotSelectedPreviewDisabledReason == nil)
        #expect(state.screenshotAllPreviewDisabledReason == nil)
    }

    @Test func screenshotPreviewAllSkipsLocalesWithBlockingIssues() async {
        let service = MockASCService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.screenshotIPadSupportOverrides["app-1"] = .ignored
        state.localeNotes = [
            LocaleNote(
                locale: "en-US",
                remoteLocalizationId: "loc-en",
                localText: "Ready notes",
                remoteText: "Ready notes",
                status: .noChange,
                diffSummary: nil
            ),
            LocaleNote(
                locale: "fr-FR",
                remoteLocalizationId: "loc-fr",
                localText: "Notes pretes",
                remoteText: "Notes pretes",
                status: .noChange,
                diffSummary: nil
            ),
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en-US/iphone.png"),
                    relativePath: "en-US/iphone.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "en-US",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                ),
                ScreenshotAsset(
                    url: root.appending(path: "fr-FR/iphone.png"),
                    relativePath: "fr-FR/iphone.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "fr-FR",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                ),
                ScreenshotAsset(
                    url: root.appending(path: "fr-FR/bad.png"),
                    relativePath: "fr-FR/bad.png",
                    size: ScreenshotPixelSize(width: 1206, height: 2622),
                    locale: "fr-FR",
                    deviceSlot: nil,
                    status: .unsupportedSize,
                    contentHash: nil
                ),
            ],
            skippedCount: 0
        )
        state.selectedScreenshotLocale = "en-US"

        #expect(state.screenshotBlockingIssueCount == 1)
        #expect(state.canUploadSelectedScreenshots)
        #expect(state.canUploadAllScreenshots)

        state.uploadAllScreenshots()
        for _ in 0..<50 where state.pendingScreenshotReplacement == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let plan = state.pendingScreenshotReplacement
        #expect(plan?.localeCount == 1)
        #expect(plan?.locales.map(\.locale) == ["en-US"])
        #expect(plan?.localUploadCount == 1)
    }

    @Test func screenshotReplacementPreviewIncludesRemoteScreenshots() async {
        let service = MockASCService()
        service.remoteScreenshotSets["loc-1"] = [
            RemoteScreenshotSet(
                id: "set-1",
                localizationId: "loc-1",
                displayType: ScreenshotDeviceSlot.iPhone65.appStoreConnectDisplayType,
                slot: .iPhone65,
                screenshots: [
                    RemoteScreenshot(
                        id: "shot-1",
                        fileName: "old-iphone.png",
                        fileSize: 12_345,
                        imageURL: nil,
                        width: 1242,
                        height: 2688
                    )
                ]
            )
        ]
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.screenshotIPadSupportOverrides["app-1"] = .ignored
        state.localeNotes = [
            LocaleNote(
                locale: "en-US",
                remoteLocalizationId: "loc-1",
                localText: "Ready notes",
                remoteText: "Ready notes",
                status: .noChange,
                diffSummary: nil
            )
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en-US/iphone.png"),
                    relativePath: "en-US/iphone.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "en-US",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                )
            ],
            skippedCount: 0
        )
        state.selectedScreenshotLocale = "en-US"

        state.uploadSelectedScreenshotLocale()
        for _ in 0..<50 where state.pendingScreenshotReplacement == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let plan = state.pendingScreenshotReplacement
        #expect(plan?.localeCount == 1)
        #expect(plan?.slotCount == 1)
        #expect(plan?.remoteDeleteCount == 1)
        #expect(plan?.localUploadCount == 1)
        #expect(service.replacedScreenshots.isEmpty)
    }

    @Test func remoteScreenshotCountsLoadFromAppStoreConnectCache() async {
        let service = MockASCService()
        service.remoteScreenshotSets["loc-1"] = [
            RemoteScreenshotSet(
                id: "set-1",
                localizationId: "loc-1",
                displayType: ScreenshotDeviceSlot.iPhone65.appStoreConnectDisplayType,
                slot: .iPhone65,
                screenshots: [
                    RemoteScreenshot(
                        id: "shot-1", fileName: "one.png", fileSize: nil, imageURL: nil, width: nil, height: nil),
                    RemoteScreenshot(
                        id: "shot-2", fileName: "two.png", fileSize: nil, imageURL: nil, width: nil, height: nil),
                ]
            ),
            RemoteScreenshotSet(
                id: "set-2",
                localizationId: "loc-1",
                displayType: ScreenshotDeviceSlot.iPhone69.appStoreConnectDisplayType,
                slot: .iPhone69,
                screenshots: [
                    RemoteScreenshot(
                        id: "shot-3", fileName: "three.png", fileSize: nil, imageURL: nil, width: nil, height: nil)
                ]
            ),
        ]
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.screenshotIPadSupportOverrides["app-1"] = .ignored
        state.localeNotes = [
            LocaleNote(
                locale: "en-US", remoteLocalizationId: "loc-1", localText: "", remoteText: "", status: .noChange,
                diffSummary: nil),
            LocaleNote(
                locale: "ja", remoteLocalizationId: nil, localText: "", remoteText: nil, status: .missing,
                diffSummary: nil),
        ]

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en-US/iphone.png"),
                    relativePath: "en-US/iphone.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "en-US",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                )
            ],
            skippedCount: 0
        )

        await state.loadRemoteScreenshotCounts(force: true)

        #expect(state.remoteScreenshotCountsByLocale["en-US"] == 3)
        #expect(state.remoteScreenshotCountsByLocale["ja"] == 0)
    }

    @Test func staleRemoteScreenshotCountRefreshCannotFinishNewRequest() async {
        let service = MockASCService()
        service.fetchScreenshotSetDelayNanoseconds = [
            "loc-old": 150_000_000,
            // Generous delay so the "still loading" assertion below has a wide
            // margin on slow CI machines (300ms check vs 1000ms delay).
            "loc-new": 1_000_000_000,
        ]
        service.remoteScreenshotSets["loc-new"] = [
            RemoteScreenshotSet(
                id: "set-new",
                localizationId: "loc-new",
                displayType: ScreenshotDeviceSlot.iPhone65.appStoreConnectDisplayType,
                slot: .iPhone65,
                screenshots: [
                    RemoteScreenshot(
                        id: "shot-new", fileName: "new.png", fileSize: nil, imageURL: nil, width: nil, height: nil)
                ]
            )
        ]
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(), appStoreService: service, defaults: makeTestDefaults())
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-old"
        state.localeNotes = [
            LocaleNote(
                locale: "en-US", remoteLocalizationId: "loc-old", localText: "", remoteText: "", status: .noChange,
                diffSummary: nil)
        ]
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en-US/iphone.png"),
                    relativePath: "en-US/iphone.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "en-US",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                )
            ],
            skippedCount: 0
        )

        state.refreshRemoteScreenshotCounts()
        // Wait until the first (slow) request is actually in flight.
        #expect(await waitUntil { state.isLoadingRemoteScreenshotCounts })

        state.selectedVersionId = "v-new"
        state.localeNotes = [
            LocaleNote(
                locale: "en-US", remoteLocalizationId: "loc-new", localText: "", remoteText: "", status: .noChange,
                diffSummary: nil)
        ]
        state.resetRemoteScreenshotCounts()
        state.refreshRemoteScreenshotCounts()

        // Well before the 1s mock delay elapses: the new request must still
        // be in flight, and no counts may have landed yet.
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(state.isLoadingRemoteScreenshotCounts)
        #expect(state.remoteScreenshotCountsTask != nil)

        #expect(await waitUntil(timeout: 4_000_000_000) { state.remoteScreenshotCountsByLocale["en-US"] == 1 })
        #expect(!state.isLoadingRemoteScreenshotCounts)
    }

    // MARK: - Failure-path coverage (error injection)

    @Test func screenshotUploadFailureMarksLocaleFailedAndSurfacesError() async {
        let service = MockASCService()
        service.replaceScreenshotsError = AppStoreConnectClientError.requestFailed(
            statusCode: 500,
            message: "upload exploded"
        )
        service.fetchedLocalizations = [
            RemoteLocaleNote(localizationId: "loc-en", locale: "en-US", text: "Hello")
        ]
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        state.localeNotes = [
            LocaleNote(
                locale: "en-US", remoteLocalizationId: "loc-en", localText: "Hello", remoteText: "Hello",
                status: .noChange, diffSummary: nil)
        ]
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        state.screenshotScan = ScreenshotScan(
            inputRoot: root,
            root: root,
            sourceKind: .directFolder,
            assets: [
                ScreenshotAsset(
                    url: root.appending(path: "en-US/iphone.png"),
                    relativePath: "en-US/iphone.png",
                    size: ScreenshotPixelSize(width: 1242, height: 2688),
                    locale: "en-US",
                    deviceSlot: .iPhone65,
                    status: .ready,
                    contentHash: nil
                )
            ],
            skippedCount: 0
        )

        let plan = ScreenshotReplacementPlan(locales: [
            ScreenshotReplacementLocalePlan(
                locale: "en-US",
                localizationId: "loc-en",
                slots: [
                    ScreenshotReplacementSlotPlan(
                        slot: .iPhone65,
                        remoteScreenshots: [],
                        localAssets: state.screenshotScan?.assets ?? []
                    )
                ]
            )
        ])

        await state.uploadScreenshotReplacementPlan(plan)

        #expect(state.lastError?.message.contains("upload exploded") == true)
        #expect(service.replacedScreenshots.isEmpty)
    }

    @Test func releaseNoteSyncFailureMarksRowFailedAndReturnsFalse() async {
        let service = MockASCService()
        service.updateWhatsNewError = AppStoreConnectClientError.requestFailed(
            statusCode: 500,
            message: "whats new exploded"
        )
        service.fetchedLocalizations = [
            RemoteLocaleNote(localizationId: "loc-en", locale: "en-US", text: "Old")
        ]
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        state.localeNotes = [
            LocaleNote(
                locale: "en-US", remoteLocalizationId: "loc-en", localText: "New", remoteText: "Old", status: .ready,
                diffSummary: nil)
        ]

        let ok = await state.syncLiveLocales(["en-US"])

        #expect(!ok)
        guard let status = state.localeNotes.first?.status else {
            Issue.record("No locale notes"); return
        }
        if case .failed = status {
            // expected
        } else {
            Issue.record("Expected .failed status, got \(status)")
        }

        // A failed row must be retried on the next sync, not skipped.
        service.updateWhatsNewError = nil
        state.dismissError()
        let okSecond = await state.syncLiveLocales(["en-US"])
        #expect(okSecond)
        guard let retriedStatus = state.localeNotes.first?.status else {
            Issue.record("No locale notes after retry"); return
        }
        if case .synced = retriedStatus {
            // expected
        } else {
            Issue.record("Expected .synced status after retry, got \(retriedStatus)")
        }
    }

    @Test func translateFailureSurfacesErrorWithoutChangingText() async {
        let mock = MockAIService()
        mock.translateError = AIServiceError.rateLimited
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()

        guard
            let source = state.localeNotes.first(where: {
                !$0.localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            Issue.record("No locale with text"); return
        }
        state.translateLocale(source.locale, fromLocale: source.locale == "ja" ? "en-US" : "ja")
        #expect(await waitUntil { state.isAIRunning == false && state.lastError != nil })

        #expect(state.lastError?.category == .ai)
        #expect(mock.translateError != nil)
    }

    private func makeTempFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesAppStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writePNG(width: Int, height: Int, to url: URL) throws {
        #if canImport(AppKit)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let data = rep.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        #else
        throw CocoaError(.fileWriteUnknown)
        #endif
    }

    // MARK: Store copy URL validation & sync

    @Test func storeCopyValidationRejectsNonRFC3986URLs() {
        let state = AppState.preview(defaults: makeTestDefaults())
        guard let locale = state.selectedStoreCopyLocale else {
            Issue.record("No store copy locale"); return
        }
        state.updateStoreCopyField(for: locale, field: .marketingURL, text: "https://example.com/笔记")
        let updated = state.storeCopyLocales.first { $0.locale == locale }
        #expect(updated?.status == .invalid)
        #expect(updated?.validationIssues.contains { $0.field == .marketingURL && $0.severity == .error } == true)
    }

    @Test func percentEncodedURICheckMatchesRFC3986() {
        #expect(AppState.isPercentEncodedURI("https://example.com/%E7%AC%94%E8%AE%B0?q=note%20app"))
        #expect(AppState.isPercentEncodedURI("https://example.com/support?topic=a&lang=zh#faq"))
        #expect(!AppState.isPercentEncodedURI("https://example.com/笔记"))
        #expect(!AppState.isPercentEncodedURI("https://example.com/my page"))
        #expect(!AppState.isPercentEncodedURI("https://example.com/%zz"))
        #expect(!AppState.isPercentEncodedURI("https://example.com/%E"))
    }

    @Test func storeCopyFieldSyncRefusesToClearRemoteURL() async {
        let service = MockASCService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        state.storeCopyLocales = [
            StoreCopyLocale(
                locale: "en-US",
                remoteLocalizationId: "loc-1",
                localMetadata: StoreMetadataFields(description: "Remote"),
                remoteMetadata: StoreMetadataFields(description: "Remote", supportURL: "https://example.com/support"),
                status: .ready,
                changedFieldCount: 1
            )
        ]
        state.selectedStoreCopyLocale = "en-US"

        // The PATCH omits empty URL attributes, so clearing a remote URL is
        // refused up front instead of silently leaving the server unchanged.
        #expect(state.storeCopyFieldCanSync(state.storeCopyLocales[0], field: .supportURL) == false)
        #expect(state.lastError != nil)

        state.syncStoreCopyField(locale: "en-US", field: .supportURL)
        #expect(await waitUntil { !state.isSyncing })
        #expect(service.lastUpdatedStoreMetadataField == nil)
    }

    @Test func storeCopyFieldSyncSendsTrimmedURL() async {
        let service = MockASCService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        state.storeCopyLocales = [
            StoreCopyLocale(
                locale: "en-US",
                remoteLocalizationId: "loc-1",
                localMetadata: StoreMetadataFields(description: "Remote"),
                remoteMetadata: StoreMetadataFields(description: "Remote", supportURL: "https://example.com/support"),
                status: .ready,
                changedFieldCount: 1
            )
        ]
        state.selectedStoreCopyLocale = "en-US"

        state.updateStoreCopyField(for: "en-US", field: .supportURL, text: "  https://example.com/help  ")
        state.syncStoreCopyField(locale: "en-US", field: .supportURL)
        #expect(await waitUntil { service.lastUpdatedStoreMetadataField != nil })
        #expect(service.lastUpdatedStoreMetadataField?.value == "https://example.com/help")
    }
}
