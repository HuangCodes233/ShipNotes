import Foundation
import Testing
@testable import ShipNotes

/// Guards against writes landing on the wrong app/version, commands firing
/// when their buttons would be disabled, and failures being reported as
/// success.
@Suite("Workflow safety")
@MainActor
struct WorkflowSafetyTests {
    private let root = URL(fileURLWithPath: NSTemporaryDirectory())

    private func makeLiveState(service: MockASCService) -> AppState {
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [
            AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app"),
            AppRecord(id: "app-2", name: "Other", bundleId: "y", platform: "iOS", iconSystemName: "app")
        ]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission),
            ReleaseVersion(id: "v-2", appId: "app-1", versionString: "2.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false
        return state
    }

    private func phoneAsset(locale: String) -> ScreenshotAsset {
        ScreenshotAsset(
            url: root.appending(path: "\(locale)/iphone.png"),
            relativePath: "\(locale)/iphone.png",
            size: ScreenshotPixelSize(width: 1242, height: 2688),
            locale: locale,
            deviceSlot: .iPhone65,
            status: .ready,
            contentHash: nil
        )
    }

    private func scan(_ assets: [ScreenshotAsset]) -> ScreenshotScan {
        ScreenshotScan(inputRoot: root, root: root, sourceKind: .directFolder, assets: assets, skippedCount: 0)
    }

    // MARK: - Screenshot uploads stay on the version they were planned for

    @Test func localizationLookupIgnoresLoadedIDsOfAnotherVersion() async throws {
        let service = MockASCService()
        let state = makeLiveState(service: service)
        state.selectedVersionId = "v-2"
        state.localeNotes = [
            LocaleNote(locale: "de-DE", remoteLocalizationId: "loc-de-v2", localText: "v2", remoteText: "v2", status: .noChange, diffSummary: nil)
        ]

        let id = try await state.ensureLocalizationId(for: "de-DE", versionId: "v-1", service: service)

        #expect(id != "loc-de-v2")
        #expect(service.createLocalizationCallCount == 1)
        // v-1's new localization must not be written into v-2's rows.
        #expect(state.localeNotes.first?.remoteLocalizationId == "loc-de-v2")

        let known = try await state.ensureLocalizationId(
            for: "de-DE",
            versionId: "v-1",
            service: service,
            knownLocalizationId: "loc-de-v1"
        )
        #expect(known == "loc-de-v1")
        #expect(service.createLocalizationCallCount == 1)
    }

    @Test func uploadRefusesPlanBuiltForAnotherVersion() async {
        let service = MockASCService()
        let state = makeLiveState(service: service)
        state.screenshotScan = scan([phoneAsset(locale: "en-US")])
        let plan = ScreenshotReplacementPlan(
            locales: [
                ScreenshotReplacementLocalePlan(
                    locale: "en-US",
                    localizationId: "loc-en-v1",
                    slots: [ScreenshotReplacementSlotPlan(slot: .iPhone65, remoteScreenshots: [], localAssets: [phoneAsset(locale: "en-US")])]
                )
            ],
            appId: "app-1",
            versionId: "v-1"
        )
        state.selectedVersionId = "v-2"

        await state.uploadScreenshotReplacementPlan(plan)

        #expect(service.replacedScreenshots.isEmpty)
        #expect(state.lastError?.message == expectedLocalized("The selected version changed. Preview the screenshot upload again."))
    }

    @Test func uploadUsesThePlannedLocalizationAndRecordsThePlannedVersion() async {
        let service = MockASCService()
        let state = makeLiveState(service: service)
        state.localeNotes = [
            LocaleNote(locale: "en-US", remoteLocalizationId: "loc-en-live", localText: "a", remoteText: "a", status: .noChange, diffSummary: nil)
        ]
        state.screenshotScan = scan([phoneAsset(locale: "en-US")])
        let plan = ScreenshotReplacementPlan(
            locales: [
                ScreenshotReplacementLocalePlan(
                    locale: "en-US",
                    localizationId: "loc-en-planned",
                    slots: [ScreenshotReplacementSlotPlan(slot: .iPhone65, remoteScreenshots: [], localAssets: [phoneAsset(locale: "en-US")])]
                )
            ],
            appId: "app-1",
            versionId: "v-1"
        )

        await state.uploadScreenshotReplacementPlan(plan)

        #expect(service.replacedScreenshots.map(\.localizationId) == ["loc-en-planned"])
        #expect(state.syncHistory.first?.versionId == "v-1")
        #expect(state.syncHistory.first?.appId == "app-1")
    }

    @Test func previewFinishingAfterVersionSwitchIsDiscarded() async {
        let service = MockASCService()
        service.fetchScreenshotSetDelayNanoseconds["loc-en"] = 200_000_000
        let state = makeLiveState(service: service)
        state.localeNotes = [
            LocaleNote(locale: "en-US", remoteLocalizationId: "loc-en", localText: "a", remoteText: "a", status: .noChange, diffSummary: nil)
        ]
        state.screenshotScan = scan([phoneAsset(locale: "en-US")])

        let preview = Task { await state.prepareScreenshotReplacementPreview(locales: ["en-US"]) }
        #expect(await waitUntil { state.isPreparingScreenshotReplacement })
        state.selectedVersionId = "v-2"
        await preview.value

        #expect(state.pendingScreenshotReplacement == nil)
        #expect(!state.isPreparingScreenshotReplacement)
    }

    @Test func previewRecordsTheSelectionItWasBuiltFor() async {
        let service = MockASCService()
        let state = makeLiveState(service: service)
        state.localeNotes = [
            LocaleNote(locale: "en-US", remoteLocalizationId: "loc-en", localText: "a", remoteText: "a", status: .noChange, diffSummary: nil),
            LocaleNote(locale: "de-DE", remoteLocalizationId: "loc-de", localText: "b", remoteText: "b", status: .noChange, diffSummary: nil)
        ]
        state.screenshotScan = scan([phoneAsset(locale: "en-US"), phoneAsset(locale: "de-DE")])

        await state.prepareScreenshotReplacementPreview(locales: ["en-US", "de-DE"])

        let plan = state.pendingScreenshotReplacement
        #expect(plan?.appId == "app-1")
        #expect(plan?.versionId == "v-1")
        #expect(plan?.locales.map(\.locale) == ["en-US", "de-DE"])
        #expect(plan?.locales.map(\.localizationId) == ["loc-en", "loc-de"])
    }

    // MARK: - Screenshots belong to one app

    @Test func switchingAppsClearsImportedScreenshots() {
        let state = AppState.preview(defaults: makeTestDefaults())
        guard let first = state.apps.first, let second = state.apps.dropFirst().first else {
            Issue.record("Sample data needs two apps")
            return
        }
        state.selectApp(first.id)
        state.screenshotScan = scan([phoneAsset(locale: "en-US")])
        state.screenshotFolder = root
        state.screenshotAILocaleOverrides = ["x": "ja"]

        // Re-selecting the same app keeps the folder.
        state.selectApp(first.id)
        #expect(state.screenshotScan != nil)

        state.selectApp(second.id)
        #expect(state.screenshotScan == nil)
        #expect(state.screenshotFolder == nil)
        #expect(state.screenshotAILocaleOverrides.isEmpty)
        #expect(state.screenshotCoverageGroups.isEmpty)
    }

    // MARK: - Submit for review reports what actually happened

    @Test func submitReturnsFalseWithAnErrorWhenReleaseNoteSyncFails() async {
        let service = MockASCService()
        service.updateWhatsNewError = AppStoreConnectClientError.requestFailed(statusCode: 500, message: "boom")
        let state = makeLiveState(service: service)
        state.localeNotes = [
            LocaleNote(locale: "de-DE", remoteLocalizationId: "loc-de", localText: "Neu", remoteText: "Alt", status: .ready, diffSummary: nil)
        ]

        let submitted = await state.submitSelectedVersionForReview(releaseType: nil)

        #expect(!submitted)
        #expect(!service.submitForReviewCalled)
        #expect(state.lastError?.message == expectedLocalized(
            "Some release notes could not be synced to App Store Connect. Fix the failed locales, then submit again."
        ))
    }

    @Test func submitClearsAStaleErrorAndReportsSuccess() async {
        let service = MockASCService()
        let state = makeLiveState(service: service)
        service.fetchedVersions = state.versionsByApp["app-1"] ?? []
        state.setError("left over from an earlier action")

        let submitted = await state.submitSelectedVersionForReview(releaseType: nil)

        #expect(submitted)
        #expect(state.lastError == nil)
    }

    // MARK: - Sync commands

    @Test func syncCommandIsDisabledForLockedVersionsAndIgnoredWhileSyncing() async {
        let service = MockASCService()
        service.updateWhatsNewDelayNanoseconds = 300_000_000
        let state = makeLiveState(service: service)
        state.localeNotes = [
            LocaleNote(locale: "de-DE", remoteLocalizationId: "loc-de", localText: "Neu", remoteText: "Alt", status: .ready, diffSummary: nil)
        ]
        #expect(state.canPerformSyncCommand)
        #expect(state.canPerformDryRunCommand)

        state.performSync()
        #expect(await waitUntil { state.isSyncing })
        let generation = state.syncGeneration
        #expect(!state.canPerformSyncCommand)

        // A second ⌘S must not cancel and restart the running sync.
        state.performSync()
        state.syncLocale("de-DE")
        #expect(state.syncGeneration == generation)
        #expect(await waitUntil { !state.isSyncing })
        #expect(state.localeNotes.first?.status == .synced)

        state.versionsByApp["app-1"] = [
            ReleaseVersion(id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .readyForSale)
        ]
        state.localeNotes[0].localText = "Noch neuer"
        state.localeNotes[0].status = .ready
        #expect(!state.canPerformSyncCommand)
        #expect(!state.canPerformDryRunCommand)
        let historyCount = state.syncHistory.count
        state.performDryRun()
        #expect(state.syncHistory.count == historyCount)
    }

    @Test func onlyTheLatestSyncClearsTheSyncingFlag() {
        let state = AppState.preview(defaults: makeTestDefaults())
        let older = state.beginSyncActivity()
        let newer = state.beginSyncActivity()

        state.endSyncActivity(older)
        #expect(state.isSyncing)

        state.endSyncActivity(newer)
        #expect(!state.isSyncing)
    }
}

/// Vision AI costs money per request; only send screenshots a match could
/// actually help with, and keep results from batches that succeeded.
@Suite("Screenshot AI matching")
@MainActor
struct ScreenshotAIMatchingTests {
    private let root = URL(fileURLWithPath: NSTemporaryDirectory())

    private final class BatchVisionService: ScreenshotVisionAIService, @unchecked Sendable {
        var isConfigured: Bool { true }
        var calls: [[String]] = []
        var failOnCall: Int?

        func classifyScreenshotLocales(
            assets: [ScreenshotAsset],
            knownLocales: [String],
            appName: String?
        ) async throws -> [ScreenshotLocaleAssignment] {
            calls.append(assets.map(\.id))
            if calls.count == failOnCall {
                throw AIServiceError.invalidResponse("batch failed")
            }
            return assets.map { ScreenshotLocaleAssignment(assetID: $0.id, locale: "ja", confidence: 0.9, reason: nil) }
        }
    }

    private func makeState(vision: BatchVisionService, locales: [String]) -> AppState {
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            visionAIService: vision,
            defaults: makeTestDefaults()
        )
        state.localeNotes = locales.map {
            LocaleNote(locale: $0, remoteLocalizationId: nil, localText: "x", remoteText: "x", status: .noChange, diffSummary: nil)
        }
        return state
    }

    private func asset(_ path: String, locale: String?, slot: ScreenshotDeviceSlot = .iPhone69) -> ScreenshotAsset {
        ScreenshotAsset(
            url: root.appending(path: path), relativePath: path,
            size: ScreenshotPixelSize(width: 1320, height: 2868),
            locale: locale, deviceSlot: slot, status: .ready, contentHash: nil
        )
    }

    @Test func missingIPadSetDoesNotMakeIPhoneScreenshotsCandidates() {
        let state = makeState(vision: BatchVisionService(), locales: ["en-US", "en-GB"])
        state.selectedAppId = "app-1"
        state.screenshotIPadSupportOverrides["app-1"] = .required
        state.screenshotScan = ScreenshotScan(
            inputRoot: root, root: root, sourceKind: .directFolder,
            assets: [asset("en-US/1.png", locale: "en-US"), asset("en-GB/1.png", locale: "en-GB")],
            skippedCount: 0
        )

        #expect(state.missingRequirementsByLocale["en-US"] == [.exact(.iPad13)])
        // Reassigning an iPhone screenshot can't provide the missing iPad set.
        #expect(state.screenshotAssetsForAIClassification.isEmpty)
    }

    @Test func assignedScreenshotIsACandidateWhenASiblingMissesItsSlot() {
        let state = makeState(vision: BatchVisionService(), locales: ["en-US", "en-GB"])
        let english = asset("en-US/1.png", locale: "en-US")
        state.screenshotScan = ScreenshotScan(
            inputRoot: root, root: root, sourceKind: .directFolder,
            assets: [english], skippedCount: 0
        )

        #expect(state.screenshotAssetsForAIClassification.map(\.id) == [english.id])
    }

    @Test func laterBatchFailureKeepsEarlierMatchesAndReportsTheError() async {
        let vision = BatchVisionService()
        vision.failOnCall = 2
        let state = makeState(vision: vision, locales: ["ja"])
        let unassigned = (1...13).map { asset("upload/\($0).png", locale: nil) }
        state.screenshotScan = ScreenshotScan(
            inputRoot: root, root: root, sourceKind: .directFolder,
            assets: unassigned, skippedCount: 0
        )

        await state.classifyScreenshotsWithAI()

        #expect(vision.calls.map(\.count) == [12, 1])
        #expect(state.screenshotAILocaleOverrides.count == 10)  // at most 10 per slot
        #expect(state.lastError?.message.contains("batch failed") == true)
        #expect(state.screenshotUploadSummary == expectedLocalized(
            "AI matched %d screenshot(s). Review the locale coverage before previewing upload.", 10
        ))
    }
}
