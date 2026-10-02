import Testing
import Foundation
@testable import ShipNotes

@Suite("Phase 4 — persistence + bulk translate + onboarding")
@MainActor
struct Phase4Tests {
    // MARK: - Sync history persistence

    @Test func syncRunRoundTripsThroughJSON() throws {
        let original = SyncRun(
            id: UUID(),
            appId: "app-1",
            versionId: "v-1-1",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_120),
            dryRun: false,
            localeResults: [
                "en-US": .succeeded,
                "zh-Hans": .failed("Over character limit"),
                "ja": .skipped
            ]
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncRun.self, from: encoded)
        #expect(decoded.id == original.id)
        #expect(decoded.appId == original.appId)
        #expect(decoded.versionId == original.versionId)
        #expect(decoded.dryRun == original.dryRun)
        #expect(decoded.localeResults["en-US"] == .succeeded)
        #expect(decoded.localeResults["zh-Hans"] == .failed("Over character limit"))
        #expect(decoded.localeResults["ja"] == .skipped)
    }

    @Test func appStatePersistsSyncRunsAcrossInstances() {
        // Use a sandboxed UserDefaults suite so the test doesn't pollute the
        // user's real defaults, and inject it into both AppState instances.
        let suiteName = "shipnotes.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = AppState.syncHistoryPersistKey

        // First instance: do a dry run, which should append to syncHistory.
        let state1 = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: defaults)
        state1.bootstrapWithMockData()
        let before = state1.syncHistory.count
        state1.performDryRun()
        #expect(state1.syncHistory.count == before + 1)

        // The run is persisted under the well-known UserDefaults key in the
        // injected suite (not the global `.standard`).
        #expect(defaults.data(forKey: key) != nil)

        // Second instance reads from the same injected suite and recovers the same head run.
        let state2 = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: defaults)
        #expect(state2.syncHistory.count >= before + 1)
    }

    // MARK: - Bulk AI translate

    @Test func translateAllEmptyLocalesFillsEveryEmptyTarget() async {
        let mock = MockAIService()
        mock.translateResult = "AUTO-TRANSLATED"
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()

        // Clear all but one locale's text so we have empty targets.
        guard let source = state.localeNotes.first(where: {
            !$0.localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            Issue.record("No locale with text to use as source"); return
        }
        for note in state.localeNotes where note.locale != source.locale {
            state.updateLocalText(for: note.locale, text: "")
        }
        let emptyTargets = state.localeNotes
            .filter { $0.locale != source.locale }
            .map(\.locale)

        state.translateAllEmptyLocales(from: source.locale)

        // Wait for the Task to drain.
        #expect(await waitUntil(timeout: 5_000_000_000) {
            emptyTargets.allSatisfy { code in
                state.localeNotes.first(where: { $0.locale == code })?.localText == "AUTO-TRANSLATED"
            }
        })
        for code in emptyTargets {
            #expect(
                state.localeNotes.first(where: { $0.locale == code })?.localText == "AUTO-TRANSLATED",
                "Expected locale \(code) to be auto-translated"
            )
        }
    }

    // MARK: - Create new App Store version

    @Test func createVersionInMockModeAppendsAndSelects() async {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        guard let appId = state.selectedAppId else {
            Issue.record("Need a selected app"); return
        }
        let before = state.versionsByApp[appId]?.count ?? 0

        await state.createVersion(versionString: "9.9.9")

        let after = state.versionsByApp[appId] ?? []
        #expect(after.count == before + 1)
        #expect(state.selectedVersion?.versionString == "9.9.9")
        #expect(state.selectedVersion?.appStoreState == .prepareForSubmission)
    }

    @Test func versionBumpSuggestion() {
        func bump(_ version: String) -> String {
            let selected = ReleaseVersion(
                id: "version-id",
                appId: "app-id",
                versionString: version,
                platform: "iOS",
                appStoreState: .prepareForSubmission
            )
            return NewVersionSheet.suggestedNextVersion(
                selectedVersion: selected,
                selectedAppId: "app-id",
                versionsByApp: ["app-id": [selected]]
            )
        }
        #expect(bump("3.0.1") == "3.0.2")
        #expect(bump("1.7") == "1.8")
        #expect(bump("2.0.9") == "2.0.10")
        #expect(bump("1.9.99") == "1.9.100")
        #expect(bump("5") == "6")
        #expect(bump("") == "")
        #expect(bump("1.0-beta") == "")  // non-numeric suffix → no suggestion
    }

    @Test func createVersionRejectsEmptyVersionString() async {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        let before = state.versionsByApp[state.selectedAppId ?? ""]?.count ?? 0
        await state.createVersion(versionString: "   ")
        #expect(state.lastError != nil)
        #expect((state.versionsByApp[state.selectedAppId ?? ""]?.count ?? 0) == before)
    }

    // MARK: - Build attachment

    @Test func loadAndAttachBuildSurfacesThroughMockService() async {
        let service = MockASCService()
        service.builds = [
            Build(id: "b-1", buildNumber: "123", marketingVersion: "1.4.0",
                  uploadedDate: Date(), expirationDate: nil, processingState: .valid),
            Build(id: "b-2", buildNumber: "124", marketingVersion: "1.4.0",
                  uploadedDate: Date(), expirationDate: nil, processingState: .processing)
        ]
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        // We need a selectedAppId / selectedVersionId to drive the load path.
        // Use a synthesised version so we don't have to bootstrap from API.
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(id: "v-1", appId: "app-1", versionString: "1.4.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false

        await state.loadBuildsForSelectedVersion()
        #expect(state.buildsByVersion["v-1"]?.count == 2)
        #expect(state.attachedBuildForSelectedVersion == nil)

        await state.setBuildForSelectedVersion("b-1")
        #expect(service.lastAttachedBuildId == "b-1")
        #expect(state.attachedBuildForSelectedVersion?.id == "b-1")

        await state.setBuildForSelectedVersion(nil)
        #expect(service.lastAttachedBuildId == nil)
        #expect(state.attachedBuildForSelectedVersion == nil)
    }

    @Test func versionCreationContextLoadsBuildsWithoutApplyingAStaleAppResponse() async {
        let service = MockASCService()
        let oldBuild = Build(
            id: "old-build",
            buildNumber: "10",
            marketingVersion: "1.0",
            platform: "IOS",
            uploadedDate: Date(),
            expirationDate: nil,
            processingState: .valid
        )
        let newBuild = Build(
            id: "new-build",
            buildNumber: "20",
            marketingVersion: "2.0",
            platform: "IOS",
            uploadedDate: Date(),
            expirationDate: nil,
            processingState: .valid
        )
        let newVersion = ReleaseVersion(
            id: "new-version",
            appId: "app-new",
            versionString: "1.9",
            platform: "iOS",
            appStoreState: .readyForSale
        )
        service.allBuildsByApp = ["app-old": [oldBuild], "app-new": [newBuild]]
        service.fetchedVersionsByApp = ["app-new": [newVersion]]
        service.fetchAllBuildsDelayNanosecondsByApp["app-old"] = 200_000_000

        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.selectedAppId = "app-old"

        let oldRequest = Task { await state.refreshVersionCreationContext() }
        #expect(await waitUntil { state.isLoadingVersionCreationContext })

        state.selectedAppId = "app-new"
        await state.refreshVersionCreationContext()
        #expect(state.uploadedBuildsByApp["app-new"] == [newBuild])
        #expect(state.versionsByApp["app-new"] == [newVersion])

        await oldRequest.value
        #expect(state.uploadedBuildsByApp["app-new"] == [newBuild])
        #expect(!state.isLoadingVersionCreationContext)
        #expect(state.versionCreationContextError == nil)
    }

    @Test func refreshAppsPreservesSelectionAndRefreshesAttachedBuild() async {
        let service = MockASCService()
        let app = AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")
        let version = ReleaseVersion(
            id: "v-1",
            appId: "app-1",
            versionString: "1.4.0",
            platform: "iOS",
            appStoreState: .prepareForSubmission
        )
        let attached = Build(
            id: "b-49",
            buildNumber: "49",
            marketingVersion: "1.4.0",
            uploadedDate: Date(),
            expirationDate: nil,
            processingState: .valid
        )
        service.fetchedApps = [app]
        service.fetchedVersions = [version]
        service.attachedBuild = attached

        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [app]
        state.versionsByApp["app-1"] = [version]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false

        await state.refreshApps()

        #expect(state.selectedAppId == "app-1")
        #expect(state.selectedVersionId == "v-1")
        #expect(state.attachedBuildForSelectedVersion?.id == "b-49")
        #expect(state.attachedBuildForSelectedVersion?.buildNumber == "49")
        #expect(service.fetchAttachedBuildCallCount == 1)
    }

    // MARK: - Auto AI fallback when parser fails

    @Test func loadFolderFallsBackToAIWhenParserCannotMatchAnyFile() async {
        let mock = MockAIService()
        mock.parseResult = [
            "en-US": "• AI got it from the weird folder",
            "zh-Hans": "• AI 从奇怪的文件夹里抽出来的"
        ]
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()

        // Synthesise the user's ReceiptCropper/Docs scenario: a folder full
        // of arbitrarily-named .md files that no rule-based parser recognises.
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "ShipNotesAITestFallback-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in [
            "planning-notes.md",
            "copy-draft.md",
            "product-positioning.md",
            "iteration-log.md"
        ] {
            try? "irrelevant body for \(name)".write(
                to: folder.appending(path: name),
                atomically: true,
                encoding: .utf8
            )
        }

        state.loadFolder(folder)

        // The AI fallback runs in a background Task; spin briefly until result lands.
        for _ in 0..<100 {
            if state.localeNotes.contains(where: { $0.localText.contains("AI got it") }) { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(state.localeNotes.first { $0.locale == "en-US" }?.localText.contains("AI got it") == true)
        #expect(state.localeNotes.first { $0.locale == "zh-Hans" }?.localText.contains("AI 从奇怪") == true)
        #expect(state.lastError == nil, "AI fallback should clear the parser error, not propagate it")
    }

    @Test func loadProjectFolderFallsBackToAIWithNestedTextFiles() async {
        let mock = MockAIService()
        mock.parseResult = ["en-US": "• AI found nested project release notes"]
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()

        let project = FileManager.default.temporaryDirectory
            .appending(path: "ShipNotesAIProjectFallback-\(UUID().uuidString)")
        let notes = project.appending(path: "Docs/Internal")
        let ignored = project.appending(path: ".git")
        try? FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
        try? "nested text that only AI should inspect".write(
            to: notes.appending(path: "misc-notes.md"),
            atomically: true,
            encoding: .utf8
        )
        try? "ignore me".write(
            to: ignored.appending(path: "release-notes.md"),
            atomically: true,
            encoding: .utf8
        )

        state.loadFolder(project)

        for _ in 0..<100 {
            if state.localeNotes.contains(where: { $0.localText.contains("nested project") }) { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(state.localeNotes.first { $0.locale == "en-US" }?.localText.contains("nested project") == true)
        #expect(mock.lastParseText?.contains("Docs/Internal/misc-notes.md") == true)
        #expect(mock.lastParseText?.contains(".git/release-notes.md") != true)
        #expect(state.lastError == nil)
    }

    @Test func screenshotReadmeDoesNotTriggerAIReleaseNotesFallback() async {
        let mock = MockAIService()
        mock.parseResult = ["en-US": "• AI should not parse screenshot docs"]
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()

        let folder = FileManager.default.temporaryDirectory
            .appending(path: "ShipNotesScreenshotReadme-\(UUID().uuidString)")
            .appending(path: "Screenshots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let readme = folder.appending(path: "README.md")
        try? """
        # Screenshot Checklist

        Recommended first set for App Store Connect:
        - iPhone 6.5 and iPhone 6.9 screenshots
        - iPad 13 screenshots when required
        """.write(to: readme, atomically: true, encoding: .utf8)

        state.loadFolder(readme)
        #expect(await waitUntil { state.lastError != nil })

        #expect(mock.lastParseText == nil)
        #expect(state.lastError?.message == expectedLocalized("This looks like screenshot documentation, not release notes. Import screenshot folders from the Screenshots tab, or choose a release-notes file."))
    }

    @Test func loadFolderSurfacesErrorWhenAINotConfiguredAndParserFails() async {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "ShipNotesNoAIFallback-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? "no parseable structure".write(
            to: folder.appending(path: "weird-name.md"),
            atomically: true,
            encoding: .utf8
        )

        state.loadFolder(folder)
        #expect(await waitUntil { state.lastError != nil },
                "Without AI configured, parser error should surface to the user")
    }

    // MARK: - Submit for Review

    @Test func reviewSubmissionCreateRequestIncludesRequiredPlatformAttribute() throws {
        let request = ASCReviewSubmissionCreateRequest(appId: "app-1", platform: "IOS")
        let encoded = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let data = try #require(json["data"] as? [String: Any])

        #expect(data["type"] as? String == "reviewSubmissions")
        // `platform` is a required attribute on reviewSubmissions — Apple
        // rejects the create without it.
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(attributes["platform"] as? String == "IOS")
        let relationships = try #require(data["relationships"] as? [String: Any])
        let app = try #require(relationships["app"] as? [String: Any])
        let appData = try #require(app["data"] as? [String: Any])
        #expect(appData["type"] as? String == "apps")
        #expect(appData["id"] as? String == "app-1")
    }

    @Test func submitForReviewSetsReleaseTypeAndCallsSubmit() async {
        let service = MockASCService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        let version = ReleaseVersion(id: "v-1", appId: "app-1", versionString: "1.4.0", platform: "iOS", appStoreState: .prepareForSubmission)
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [version]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        service.fetchedVersions = [version]

        await state.submitSelectedVersionForReview(releaseType: .afterApproval)
        #expect(service.lastReleaseType == "AFTER_APPROVAL")
        #expect(service.submitForReviewCalled == true)
        #expect(service.lastSubmitPlatform == "IOS")
        #expect(state.lastError == nil)
    }

    @Test func submitForReviewTreatsApple500AsSuccessWhenRefreshShowsSubmittedState() async {
        let service = MockASCService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(id: "v-1", appId: "app-1", versionString: "1.4.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        service.submitForReviewError = AppStoreConnectClientError.requestFailed(
            statusCode: 500,
            message: "UNEXPECTED_ERROR"
        )
        service.fetchedVersions = [
            ReleaseVersion(id: "v-1", appId: "app-1", versionString: "1.4.0", platform: "iOS", appStoreState: .waitingForReview)
        ]

        await state.submitSelectedVersionForReview(releaseType: .afterApproval)

        #expect(service.submitForReviewCalled == true)
        #expect(state.lastError == nil)
        #expect(state.selectedVersion?.appStoreState == .waitingForReview)
    }

    @Test func submittedVersionCannotBeSubmittedAgain() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(id: "v-1", appId: "app-1", versionString: "1.4.0", platform: "iOS", appStoreState: .waitingForReview)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"

        #expect(state.selectedVersion?.canEditMetadata == true)
        #expect(state.canSubmitSelectedForReview == false)
    }

    @Test func firstReleasePreflightDoesNotRequireWhatsNew() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        let firstVersion = ReleaseVersion(
            id: "v-1",
            appId: "app-1",
            versionString: "1.0.0",
            platform: "iOS",
            appStoreState: .prepareForSubmission
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [firstVersion]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.localeNotes = [
            LocaleNote(locale: "en-US", localPath: nil, remoteLocalizationId: nil, localText: "", remoteText: nil, status: .missing),
            LocaleNote(locale: "ja", localPath: nil, remoteLocalizationId: nil, localText: "", remoteText: nil, status: .missing)
        ]

        #expect(firstVersion.looksLikeFirstMarketingVersion == true)
        #expect(state.selectedVersionIsFirstRelease == true)
        #expect(state.releaseNotesReadyForReviewSubmission == true)
        #expect(state.releaseNotesReviewChecklistLabel == expectedLocalized("First release: What's New is not required"))
    }

    @Test func laterReleasePreflightStillRequiresWhatsNew() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        let liveVersion = ReleaseVersion(
            id: "v-live",
            appId: "app-1",
            versionString: "1.0.0",
            platform: "iOS",
            appStoreState: .readyForSale
        )
        let updateVersion = ReleaseVersion(
            id: "v-update",
            appId: "app-1",
            versionString: "1.1.0",
            platform: "iOS",
            appStoreState: .prepareForSubmission
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [updateVersion, liveVersion]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-update"
        state.localeNotes = [
            LocaleNote(locale: "en-US", localPath: nil, remoteLocalizationId: nil, localText: "", remoteText: nil, status: .missing)
        ]

        #expect(updateVersion.looksLikeFirstMarketingVersion == false)
        #expect(state.selectedVersionIsFirstRelease == false)
        #expect(state.releaseNotesReadyForReviewSubmission == false)
        #expect(state.releaseNotesReviewChecklistLabel == expectedLocalized("Locale release notes ready: %1$d / %2$d", 0, 1))
    }

    @Test func aiCounterIncrementsOnEveryAICall() async {
        let mock = MockAIService()
        mock.translateResult = "ok"
        let state = AppState(aiService: mock, defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        state.resetAICallCount()

        guard let source = state.localeNotes.first(where: {
            !$0.localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            Issue.record("Need a source locale"); return
        }
        // Pick a target distinct from source so translate isn't a no-op.
        guard let target = state.localeNotes.first(where: { $0.locale != source.locale })?.locale else {
            Issue.record("Need two locales"); return
        }

        let before = state.aiCallCount
        state.translateLocale(target, fromLocale: source.locale)
        for _ in 0..<50 where state.aiCallCount == before {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(state.aiCallCount == before + 1)
    }

    @Test func translateAllEmptyLocalesDoesNothingWhenAIMissing() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.bootstrapWithMockData()
        guard let source = state.localeNotes.first(where: {
            !$0.localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            Issue.record("No source"); return
        }
        for note in state.localeNotes where note.locale != source.locale {
            state.updateLocalText(for: note.locale, text: "")
        }

        state.translateAllEmptyLocales(from: source.locale)
        #expect(state.lastError != nil)
    }
}
