import Foundation
import Observation
import OSLog
#if canImport(AppKit)
import AppKit
#endif

struct LocaleNotesStats: Equatable {
    var readyCount = 0
    var needsReviewCount = 0
    var overLimitCount = 0
    var missingCount = 0

    /// Pure tally of per-locale editor status. Kept off AppState so stats can
    /// be unit-tested without spinning up the whole observable graph.
    static func from(_ notes: [LocaleNote]) -> LocaleNotesStats {
        var stats = LocaleNotesStats()
        for note in notes {
            switch note.status {
            case .ready: stats.readyCount += 1
            case .needsReview: stats.needsReviewCount += 1
            case .overLimit: stats.overLimitCount += 1
            case .missing: stats.missingCount += 1
            default: break
            }
        }
        return stats
    }
}

struct StoreCopyStats: Equatable {
    var readyCount = 0
    var issueCount = 0
    var pendingSyncCount = 0

    /// Pure tally of store-copy readiness. Kept off AppState for the same
    /// reason as `LocaleNotesStats.from`.
    static func from(_ locales: [StoreCopyLocale]) -> StoreCopyStats {
        var stats = StoreCopyStats()
        for locale in locales {
            let status = locale.status
            if status == .ready || status == .needsReview || status == .synced || status == .noChange {
                stats.readyCount += 1
            }
            if status == .ready || status == .needsReview {
                stats.pendingSyncCount += 1
            }
            for issue in locale.validationIssues {
                if issue.severity == .error {
                    stats.issueCount += 1
                }
            }
        }
        return stats
    }
}

enum SettingsKey {
    static let stripMarkdownOnSync = "shipnotes.stripMarkdownOnSync"
    static let aiVisionProvider = "shipnotes.ai.vision.provider"
    static let aiCallCount = "shipnotes.ai.callCount"
    static let screenshotIPadSupportOverrides = "shipnotes.screenshot.iPadSupportOverrides"
    static let hasSeenOnboarding = "shipnotes.hasSeenOnboarding"
}

struct PendingAppleAdsStatusChange: Equatable, Sendable {
    var campaignId: String
    var status: String
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case releaseNotes
    case storeCopy
    case screenshots
    case ads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .releaseNotes: L("Release Notes")
        case .storeCopy: L("Store Copy")
        case .screenshots: L("Screenshots")
        case .ads: L("Ads")
        }
    }
}

internal extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

internal let sharedScreenshotLanguageDefaults: [String: String] = [
    "en": "en-US",
    "es": "es-ES",
    "fr": "fr-FR",
    "pt": "pt-BR"
]

internal enum CredentialLoadResult: Sendable {
    case success(AppStoreConnectCredentials?)
    case failure(AppStoreConnectCredentialError)
}

@MainActor
@Observable
final class AppState {

    var accounts: [Account] = []
    var apps: [AppRecord] = []
    var versionsByApp: [String: [ReleaseVersion]] = [:]

    var selectedAppId: String?
    var selectedVersionId: String?
    var selectedLocale: String?
    var workspaceMode: WorkspaceMode = .releaseNotes

    var sourceFolder: URL?
    var sourceDescription: String?
    var watching: Bool = false

    var screenshotFolder: URL?
    var screenshotScan: ScreenshotScan?
    var selectedScreenshotLocale: String?
    var screenshotOrderByGroup: [String: [String]] = [:]
    var selectedScreenshotAssetId: String?
    var screenshotFocusTargetID: String?
    var screenshotUploadSummary: String?
    /// In-flight upload progress (message + start time) for the top banner, so
    /// long multi-locale uploads show "what" and "how long" instead of a bare
    /// spinner. Reuses the AIActivity shape (startedAt + message).
    var screenshotUploadActivity: AIActivity?
    /// Identity of the current screenshot-upload run. Progress callbacks from
    /// a finished run check this before touching `screenshotUploadActivity`,
    /// so a late `onProgress` hop can't resurrect a banner that the run's
    /// `defer` already cleared.
    @ObservationIgnored internal var screenshotUploadRequestID: UUID?
    /// Identity of the latest replacement-preview request. A preview that
    /// finishes after a newer request (or a selection change) is discarded.
    @ObservationIgnored internal var screenshotPreviewRequestID: UUID?
    var pendingScreenshotReplacement: ScreenshotReplacementPlan?
    var screenshotAISharedAssetIDs: Set<String> = []
    var screenshotAILocaleOverrides: [String: String] = [:]
    var screenshotIPadSupportOverrides: [String: ScreenshotIPadSupportOverride] = [:]
    var screenshotIPadSupportDetections: [String: ScreenshotIPadSupportDetection] = [:]
    var remoteScreenshotCountsByLocale: [String: Int] = [:]
    var isLoadingRemoteScreenshotCounts: Bool = false

    var localeNotes: [LocaleNote] = []
    var storeCopyLocales: [StoreCopyLocale] = []
    var selectedStoreCopyLocale: String?
    var storeCopySourceURL: URL?
    var storeCopySourceDescription: String?
    var syncHistory: [SyncRun] = []
    var lastError: AppError?
    var pendingImport: ParsedReleaseNotes?
    var pendingImportURL: URL?
    var pendingImportSelections: [String: String] = [:]
    var pendingImportSelectedLocale: String?

    var isUsingMockData: Bool = true
    var isLoadingRemote: Bool = false
    var isSyncing: Bool = false
    var isAIRunning: Bool = false
    var isLoadingBuilds: Bool = false
    var isLoadingVersionCreationContext: Bool = false
    var isSubmittingForReview: Bool = false
    var isUploadingScreenshots: Bool = false
    var isPreparingScreenshotReplacement: Bool = false
    var isScanningScreenshots: Bool = false

    /// Visible progress description for an in-flight AI call. Cleared as
    /// soon as the task finishes (success or failure). Used by the top
    /// progress banner so the user can see "what" and "how long".
    var aiActivity: AIActivity?

    struct AIActivity: Hashable, Sendable {
        let startedAt: Date
        let message: String
    }

    /// Total number of AI calls made by this install. Persisted across launches.
    var aiCallCount: Int = 0

    /// Cache of builds eligible for each App Store version (keyed by versionId).
    /// Populated lazily when the user opens the Build picker.
    var buildsByVersion: [String: [Build]] = [:]
    /// Build currently attached to a given App Store version, when known.
    var attachedBuildByVersion: [String: Build] = [:]
    /// Uploaded builds grouped by app. The marketing version comes from each
    /// build's prerelease-version relationship.
    var uploadedBuildsByApp: [String: [Build]] = [:]
    var versionCreationContextError: String?
    var connectionStatus: String = "Using mock sample data"
    var credentialSummary: AppStoreConnectCredentialSummary?

    var appleAdsCampaigns: [AppleAdsCampaign] = []
    @ObservationIgnored var adsRefreshID = UUID()
    @ObservationIgnored var adsDetailsID = UUID()
    @ObservationIgnored var adsKeywordsID = UUID()
    var appleAdsMetricsByCampaign: [String: AppleAdsCampaignMetrics] = [:]
    var appleAdsReportRange: AppleAdsReportRange = .days7
    var selectedAppleAdsCampaignId: String?
    var appleAdsAdGroups: [AppleAdsAdGroup] = []
    var selectedAppleAdsAdGroupId: String?
    var appleAdsKeywords: [AppleAdsKeyword] = []
    var appleAdsSearchTerms: [AppleAdsSearchTerm] = []
    var appleAdsSuggestions: [AppleAdsKeywordSuggestion] = []
    var appleAdsSelectedSuggestionTexts: Set<String> = []
    var appleAdsAccounts: [AppleAdsAccount] = []
    var appleAdsConnectionStatus: String = "Using sample Apple Ads data"
    var appleAdsCredentialSummary: AppleAdsCredentialSummary?
    var appleAdsAccountCapabilities: AppleAdsAccount?
    var selectedAppleAdsAccountId: String?
    var isUsingSampleAds: Bool = true
    var isLoadingAds: Bool = false
    var showPromoteVersionSheet = false
    var showAppleAdsKeywordConfirm = false
    var pendingAppleAdsStatusChange: PendingAppleAdsStatusChange?
    var offerPromoteAfterSubmit = false

    var selectedAIProvider: AIProvider = .none
    var selectedVisionAIProvider: AIProvider = .none

    @ObservationIgnored internal let parser = ReleaseNotesParser()
    @ObservationIgnored internal let storeCopyParser = StoreCopyParser()
    @ObservationIgnored internal let diff = DiffEngine()
    @ObservationIgnored internal let validator = ValidationEngine()
    @ObservationIgnored internal let fileWatcher = FileWatcher()
    @ObservationIgnored internal let credentialStore: any AppStoreConnectCredentialStoring
    @ObservationIgnored internal let aiKeychainStore: any AIKeychainStoring
    @ObservationIgnored var aiService: any AIService {
        didSet { aiServiceRevision &+= 1 }
    }
    @ObservationIgnored var visionAIService: any ScreenshotVisionAIService {
        didSet { aiServiceRevision &+= 1 }
    }
    /// Observed stand-in for the unobservable service values above, so views
    /// reading `isAIConfigured` update as soon as a key is saved or removed.
    internal var aiServiceRevision = 0
    @ObservationIgnored internal var appStoreService: (any AppStoreConnectServicing)?
    @ObservationIgnored internal let appleAdsCredentialStore: any AppleAdsCredentialStoring
    @ObservationIgnored internal var appleAdsService: (any AppleAdsServicing)?
    @ObservationIgnored internal var remoteNotesByLocale: [String: RemoteLocaleNote] = [:]
    @ObservationIgnored internal var screenshotScanRequestID: UUID?
    @ObservationIgnored internal var screenshotScanTask: Task<Void, Never>?
    @ObservationIgnored internal var syncTask: Task<Void, Never>?
    @ObservationIgnored internal var syncGeneration: UUID = UUID()
    @ObservationIgnored internal var syncActivityToken: UUID?
    @ObservationIgnored internal var folderLoadRequestID: UUID?
    @ObservationIgnored internal var versionCreationContextRequestID: UUID?
    @ObservationIgnored internal var screenshotCoverageGroupsCache: ScreenshotCoverageGroupsCache?

    func handleError(_ error: Error) {
        if Self.isCancellation(error) { return }
        let category: AppError.Category
        switch error {
        case is URLError:
            category = .network
        case let nsError as NSError where nsError.domain == NSURLErrorDomain:
            category = .network
        case let nsError as NSError where nsError.domain == NSCocoaErrorDomain:
            category = .fileIO
        case let aiError as AIServiceError:
            // Network-layer failures from the AI provider are connectivity
            // issues, not AI-specific rejections.
            if case .networkError = aiError {
                category = .network
            } else {
                category = .ai
            }
        case let asc as AppStoreConnectClientError:
            switch asc {
            case .connectionTimedOut, .networkError:
                category = .network
            default:
                category = .appStoreConnect
            }
        case is AppStoreConnectCredentialError:
            category = .auth
        case is AppleAdsCredentialError:
            category = .auth
        case let ads as AppleAdsClientError:
            switch ads {
            case .connectionTimedOut, .networkError:
                category = .network
            case .unauthorized, .missingAdAccount:
                category = .auth
            default:
                category = .unknown
            }
        default:
            category = .unknown
        }
        self.lastError = AppError(
            error.localizedDescription,
            category: category,
            recoverySuggestion: Self.recoverySuggestion(for: category),
            isRetryable: category == .network || category == .appStoreConnect
        )
    }

    private static func recoverySuggestion(for category: AppError.Category) -> String? {
        switch category {
        case .network:
            return L("Check your internet connection and try again.")
        case .auth:
            return L("Open Settings and re-enter your App Store Connect credentials.")
        case .ai:
            return L("Open Settings -> AI to verify your API key and provider.")
        case .appStoreConnect:
            return nil
        case .validation, .fileIO, .unknown:
            return nil
        }
    }
    @ObservationIgnored internal var screenshotIssuesCache: ScreenshotIssuesCache?
    @ObservationIgnored internal var remoteScreenshotCountsTask: Task<Void, Never>?
    @ObservationIgnored internal var remoteScreenshotCountsVersionId: String?
    @ObservationIgnored internal var remoteScreenshotCountsRequestID: UUID?
    /// Backing store for persisted settings (sync history, AI call count,
    /// screenshot overrides, strip-markdown flag). Injectable so tests can use
    /// an ephemeral `UserDefaults` suite instead of polluting `.standard`.
    @ObservationIgnored internal let defaults: UserDefaults

    init(
        credentialStore: any AppStoreConnectCredentialStoring = KeychainCredentialStore(),
        aiKeychainStore: any AIKeychainStoring = AIKeychainStore(),
        aiService: (any AIService)? = nil,
        visionAIService: (any ScreenshotVisionAIService)? = nil,
        appStoreService: (any AppStoreConnectServicing)? = nil,
        appleAdsCredentialStore: any AppleAdsCredentialStoring = AppleAdsKeychainStore(),
        appleAdsService: (any AppleAdsServicing)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.credentialStore = credentialStore
        self.aiKeychainStore = aiKeychainStore
        self.appStoreService = appStoreService
        self.appleAdsCredentialStore = appleAdsCredentialStore
        self.defaults = defaults
        self.aiService = aiService ?? UnconfiguredAIService()
        self.visionAIService = visionAIService ?? UnconfiguredScreenshotVisionAIService()
        self.selectedVisionAIProvider = Self.loadStoredVisionAIProvider(defaults: defaults)
        // An injected client (tests or a live session) is the live path.
        // Sample data is installed later via `bootstrapWithMockData()`, which
        // sets `isUsingMockData` back to true even though a service is present.
        if appStoreService != nil {
            isUsingMockData = false
            connectionStatus = "Connected"
        }
        if let appleAdsService {
            self.appleAdsService = appleAdsService
            isUsingSampleAds = false
            appleAdsConnectionStatus = "Connected to Apple Ads"
        } else {
            self.appleAdsService = SampleAppleAdsService()
            isUsingSampleAds = true
        }
        // Restore sync runs from disk so the history sheet isn't empty after relaunch.
        self.loadPersistedSyncHistory()
        self.aiCallCount = defaults.integer(forKey: SettingsKey.aiCallCount)
        self.screenshotIPadSupportOverrides = Self.loadScreenshotIPadSupportOverrides(defaults: defaults)
    }

    var isAIConfigured: Bool {
        _ = aiServiceRevision
        return aiService.isConfigured
    }

    var isVisionAIConfigured: Bool {
        _ = aiServiceRevision
        return visionAIService.isConfigured
    }

    /// Effective model name used by the current AI provider (reads the
    /// provider-specific UserDefaults key, falls back to the provider's default).
    var currentAIModel: String {
        aiModel(for: selectedAIProvider)
    }

    var currentVisionAIModel: String {
        aiModel(for: selectedVisionAIProvider, role: .vision)
    }

    var selectedApp: AppRecord? {
        guard let id = selectedAppId else { return nil }
        return apps.first { $0.id == id }
    }

    var selectedVersion: ReleaseVersion? {
        guard let appId = selectedAppId, let versionId = selectedVersionId else { return nil }
        return versionsByApp[appId]?.first { $0.id == versionId }
    }

    var selectedLocaleNote: LocaleNote? {
        guard let code = selectedLocale else { return nil }
        return localeNotes.first { $0.locale == code }
    }

    var selectedStoreCopy: StoreCopyLocale? {
        guard let code = selectedStoreCopyLocale else { return nil }
        return storeCopyLocales.first { $0.locale == code }
    }

    /// The group the screenshot workspace shows: the selected locale, or the
    /// first group when the selection isn't (or is no longer) a coverage
    /// locale. Toolbar actions and the workspace must agree on this.
    var selectedScreenshotGroup: ScreenshotLocaleGroup? {
        let groups = screenshotCoverageGroups
        return groups.first { $0.locale == selectedScreenshotLocale } ?? groups.first
    }

    var localeNotesStats: LocaleNotesStats {
        LocaleNotesStats.from(localeNotes)
    }

    var storeCopyStats: StoreCopyStats {
        StoreCopyStats.from(storeCopyLocales)
    }

    var requiredScreenshotSlotGroups: [ScreenshotSlotRequirement] {
        ScreenshotSlotRequirement.groups(
            platform: selectedScreenshotPlatform,
            requiresIPad: screenshotRequiresIPad
        )
    }

    var expectedScreenshotSlots: [ScreenshotDeviceSlot] {
        var slots: [ScreenshotDeviceSlot] = []
        for requirement in requiredScreenshotSlotGroups {
            for slot in requirement.slots where !slots.contains(slot) {
                slots.append(slot)
            }
        }
        return slots
    }

    var visibleScreenshotSlots: [ScreenshotDeviceSlot] {
        getScreenshotIssuesCache()?.visibleScreenshotSlots ?? expectedScreenshotSlots
    }

    var uploadableScreenshotSlots: [ScreenshotDeviceSlot] {
        visibleScreenshotSlots.filter { slot in
            slot != .iPad13 || screenshotRequiresIPad
        }
    }

    var canConfigureScreenshotIPadSupport: Bool {
        !selectedScreenshotPlatformContains("mac")
            && !selectedScreenshotPlatformContains("tv")
            && !selectedScreenshotPlatformContains("vision")
            && !selectedScreenshotPlatformContains("watch")
    }

    var screenshotIPadSupportOverride: ScreenshotIPadSupportOverride {
        guard let key = selectedScreenshotRequirementKey else { return .automatic }
        return screenshotIPadSupportOverrides[key] ?? .automatic
    }

    var selectedScreenshotIPadSupportDetection: ScreenshotIPadSupportDetection {
        guard let key = selectedScreenshotRequirementKey else { return .unknown }
        return screenshotIPadSupportDetections[key] ?? .unknown
    }

    var screenshotRequiresIPad: Bool {
        guard canConfigureScreenshotIPadSupport else { return false }
        switch screenshotIPadSupportOverride {
        case .automatic:
            return selectedScreenshotIPadSupportDetection.supportsIPad == true
        case .required:
            return true
        case .ignored:
            return false
        }
    }

    var screenshotIPadRequirementSummary: String {
        guard canConfigureScreenshotIPadSupport else {
            return L("iPad screenshots are not used for this platform.")
        }
        switch screenshotIPadSupportOverride {
        case .automatic:
            switch selectedScreenshotIPadSupportDetection {
            case .supported:
                return L("Auto detected: iPad 13\" screenshots are required.")
            case .unsupported:
                return L("Auto detected: iPad screenshots are ignored.")
            case .unknown:
                return L("Auto detection is unknown. iPad screenshots are ignored for now.")
            }
        case .required:
            return L("Manual setting: iPad 13\" screenshots are required.")
        case .ignored:
            return L("Manual setting: iPad screenshots are ignored.")
        }
    }

    internal var selectedScreenshotRequirementKey: String? {
        selectedApp?.id ?? selectedAppId ?? selectedApp?.bundleId
    }

    internal var selectedScreenshotPlatform: String {
        (selectedVersion?.platform ?? selectedApp?.platform ?? "").lowercased()
    }

    internal func getScreenshotIssuesCache() -> ScreenshotIssuesCache? {
        guard let scan = screenshotScan else {
            screenshotIssuesCache = nil
            return nil
        }
        let groups = screenshotCoverageGroups
        let requiredGroups = requiredScreenshotSlotGroups
        guard let coverageKey = screenshotCoverageGroupsCache?.key else {
            return nil
        }
        let key = ScreenshotIssuesCacheKey(
            coverageKey: coverageKey,
            requiredGroups: requiredGroups
        )
        if let cache = screenshotIssuesCache, cache.key == key {
            return cache
        }
        let issues = scan.issues(requiredGroups: requiredGroups, localeGroups: groups)
        let blocking = issues.filter { $0.severity == .error }.count
        let warning = issues.filter { $0.severity == .warning }.count

        var missing: [String: [ScreenshotSlotRequirement]] = [:]
        missing.reserveCapacity(groups.count)
        for group in groups where !group.isUnassigned {
            missing[group.locale] = requiredGroups.filter { requirement in
                !requirement.isSatisfied(by: group.assets)
            }
        }

        var slots = requiredGroups.flatMap { $0.slots }
        for asset in scan.assets {
            guard let slot = asset.deviceSlot, !slots.contains(slot) else { continue }
            slots.append(slot)
        }

        let cache = ScreenshotIssuesCache(
            key: key,
            issues: issues,
            blockingIssueCount: blocking,
            warningCount: warning,
            missingRequirementsByLocale: missing,
            visibleScreenshotSlots: slots,
            aiClassificationCandidates: makeScreenshotAIClassificationCandidates(
                scan: scan,
                groups: groups,
                missingRequirementsByLocale: missing
            )
        )
        screenshotIssuesCache = cache
        return cache
    }

    var screenshotCoverageGroups: [ScreenshotLocaleGroup] {
        guard let scan = screenshotScan else {
            screenshotCoverageGroupsCache = nil
            return []
        }
        let locales = screenshotCoverageLocales
        let key = screenshotCoverageGroupsCacheKey(scan: scan, locales: locales)
        if let cache = screenshotCoverageGroupsCache, cache.key == key {
            return cache.groups
        }
        let coverage = makeScreenshotCoverage(scan: scan, locales: locales)
        screenshotCoverageGroupsCache = ScreenshotCoverageGroupsCache(
            key: key,
            groups: coverage.groups,
            localeByAssetID: coverage.localeByAssetID
        )
        return coverage.groups
    }

    var screenshotIssues: [ScreenshotIssue] {
        getScreenshotIssuesCache()?.issues ?? []
    }

    var screenshotBlockingIssueCount: Int {
        getScreenshotIssuesCache()?.blockingIssueCount ?? 0
    }

    var screenshotWarningCount: Int {
        getScreenshotIssuesCache()?.warningCount ?? 0
    }

    var screenshotReadyForSubmission: Bool {
        screenshotScan != nil && screenshotBlockingIssueCount == 0
    }

    var screenshotChecklistLabel: String {
        guard screenshotScan != nil else {
            return L("Screenshots not checked in ShipNotes")
        }
        if screenshotBlockingIssueCount == 0 {
            if screenshotWarningCount == 0 {
                return L("Screenshots ready")
            }
            return L("Screenshots ready with %d warning(s)", screenshotWarningCount)
        }
        return L("Screenshots have %d blocking issue(s)", screenshotBlockingIssueCount)
    }

    var canUploadSelectedScreenshots: Bool {
        screenshotSelectedPreviewDisabledReason == nil
    }

    var screenshotSelectedPreviewDisabledReason: String? {
        screenshotPreviewControlsState.selectedDisabledReason
    }

    var canUploadAllScreenshots: Bool {
        screenshotAllPreviewDisabledReason == nil
    }

    var screenshotAllPreviewDisabledReason: String? {
        screenshotPreviewControlsState.allDisabledReason
    }

    var screenshotAIClassificationHelp: String {
        guard screenshotScan != nil else {
            return L("Import screenshots before using AI matching.")
        }
        guard isVisionAIConfigured else {
            return L("Configure a vision AI model in Settings before matching screenshots.")
        }
        guard !screenshotAssetsForAIClassification.isEmpty else {
            return L("No screenshots need AI matching.")
        }
        return L("Use the configured vision AI model to match unclear or missing-language screenshots to App Store locales.")
    }

    var canClassifyScreenshotsWithAI: Bool {
        screenshotScan != nil
            && isVisionAIConfigured
            && !isAIRunning
            && !screenshotAssetsForAIClassification.isEmpty
    }

    static var preview: AppState {
        let state = AppState()
        state.bootstrapWithMockData()
        return state
    }

    /// Test-only variant of `preview` with injectable dependencies, so tests
    /// don't write fake SyncRuns into the real `.standard` UserDefaults (or
    /// touch the real Keychain).
    static func preview(
        aiKeychainStore: any AIKeychainStoring = AIKeychainStore(),
        appStoreService: (any AppStoreConnectServicing)? = nil,
        defaults: UserDefaults
    ) -> AppState {
        let state = AppState(
            aiKeychainStore: aiKeychainStore,
            appStoreService: appStoreService,
            defaults: defaults
        )
        state.bootstrapWithMockData()
        return state
    }

    // MARK: - AI provider
    // AI provider keychain reload, endpoint/model persistence, connection
    // testing, AI-driven parse/translate/optimize, and store-copy parse live
    // in AppState+AI.swift.

    // MARK: - Submit for Review

    enum ReleaseType: String, CaseIterable, Hashable, Sendable {
        case manual = "MANUAL"
        case afterApproval = "AFTER_APPROVAL"
        case scheduled = "SCHEDULED"
    }

    /// Locales the user has edited locally but hasn't pushed to App Store
    /// Connect yet. Submit auto-syncs these so Apple sees the latest content.
    var pendingSyncLocaleCount: Int {
        let stats = localeNotesStats
        return stats.readyCount + stats.needsReviewCount
    }

    var selectedVersionIsFirstRelease: Bool {
        guard let appId = selectedAppId,
              let version = selectedVersion,
              version.looksLikeFirstMarketingVersion else {
            return false
        }
        let releasedStates: Set<AppStoreVersionState> = [
            .accepted,
            .pendingAppleRelease,
            .pendingDeveloperRelease,
            .readyForSale,
            .developerRemovedFromSale,
            .removedFromSale
        ]
        let appVersions = versionsByApp[appId] ?? []
        return !appVersions.contains { candidate in
            candidate.id != version.id && releasedStates.contains(candidate.appStoreState)
        }
    }

    internal var reviewReadyLocaleNoteCount: Int {
        localeNotes.filter { note in
            note.status == .ready || note.status == .synced || note.status == .noChange
        }.count
    }

    var releaseNotesReadyForReviewSubmission: Bool {
        if selectedVersionIsFirstRelease { return true }
        return reviewReadyLocaleNoteCount == localeNotes.count && !localeNotes.isEmpty
    }

    var releaseNotesReviewChecklistLabel: String {
        if selectedVersionIsFirstRelease {
            return L("First release: What's New is not required")
        }
        return L("Locale release notes ready: %1$d / %2$d", reviewReadyLocaleNoteCount, localeNotes.count)
    }

    /// True only when the currently-selected version meets the bare minimum
    /// preconditions ShipNotes can verify before calling submit. Apple's API
    /// may still reject for other reasons (e.g. missing screenshots) — those
    /// errors will surface in `lastError` when the user clicks Submit anyway.
    var canSubmitSelectedForReview: Bool {
        guard let version = selectedVersion else { return false }
        return version.canEditMetadata
            && !version.appStoreState.isSubmittedForReview
            && !isSubmittingForReview
    }

    // MARK: - Builds

    /// Currently-attached build for the selected version, if any.
    var attachedBuildForSelectedVersion: Build? {
        guard let id = selectedVersionId else { return nil }
        return attachedBuildByVersion[id]
    }

    // Build picker fetch/refresh/attach logic lives in
    // AppState+AppStoreConnect.swift.

    internal var screenshotKnownVersionLocales: [String] {
        let releaseNoteLocales = uniqueLocales(localeNotes.map(\.locale))
        if !releaseNoteLocales.isEmpty {
            return releaseNoteLocales
        }

        let storeCopyLocales = uniqueLocales(storeCopyLocales.map(\.locale))
        if !storeCopyLocales.isEmpty {
            return storeCopyLocales
        }

        return uniqueLocales(remoteNotesByLocale.keys.sorted())
    }

    internal var screenshotCoverageLocales: [String] {
        let versionLocales = screenshotKnownVersionLocales
        if !versionLocales.isEmpty {
            return versionLocales
        }
        return uniqueLocales(
            screenshotScan?.localeGroups.compactMap { $0.isUnassigned ? nil : $0.locale } ?? []
        )
    }

    internal var screenshotAssetsForAIClassification: [ScreenshotAsset] {
        getScreenshotIssuesCache()?.aiClassificationCandidates ?? []
    }

    /// Unassigned screenshots, plus assigned ones that could fill a gap: a
    /// sibling locale of the same language misses a required size in exactly
    /// this screenshot's slot (AI may find it belongs there). Reassigning a
    /// screenshot of any other slot can't satisfy the requirement, and
    /// including those turned a missing iPad set into "send every iPhone
    /// screenshot to the vision model".
    private func makeScreenshotAIClassificationCandidates(
        scan: ScreenshotScan,
        groups: [ScreenshotLocaleGroup],
        missingRequirementsByLocale: [String: [ScreenshotSlotRequirement]]
    ) -> [ScreenshotAsset] {
        let localeByAssetID = screenshotCoverageGroupsCache?.localeByAssetID ?? [:]
        func locale(of asset: ScreenshotAsset) -> String? {
            if let cached = localeByAssetID[asset.id] { return cached }
            return canonicalScreenshotLocale(for: asset)
        }

        let classifiable = scan.assets.filter { $0.deviceSlot != nil && $0.status == .ready }
        var candidates = classifiable.filter { locale(of: $0) == nil }

        var missingSlotsByLanguage: [String: Set<ScreenshotDeviceSlot>] = [:]
        for group in groups where !group.isUnassigned {
            guard let missing = missingRequirementsByLocale[group.locale], !missing.isEmpty,
                  let language = languageCode(for: group.locale) else { continue }
            missingSlotsByLanguage[language, default: []].formUnion(missing.flatMap(\.slots))
        }

        if !missingSlotsByLanguage.isEmpty {
            candidates.append(contentsOf: classifiable.filter { asset in
                guard let slot = asset.deviceSlot,
                      let assetLocale = locale(of: asset),
                      let language = languageCode(for: assetLocale) else {
                    return false
                }
                return missingSlotsByLanguage[language]?.contains(slot) == true
            })
        }

        return uniqueScreenshotAssets(candidates)
    }

    func dismissError() { lastError = nil }

    /// Convenience setter for user-facing / validation messages that are not a
    /// thrown `Error`. Prefer `handleError(_:)` for caught errors so category
    /// and retryability stay accurate.
    func setError(
        _ message: String,
        category: AppError.Category = .validation,
        isRetryable: Bool = false
    ) {
        lastError = AppError(message, category: category, isRetryable: isRetryable)
    }

    /// Clear all per-workspace selection state and loaded content. Called from
    /// several app/version switching paths in AppState+AppStoreConnect, so the
    /// "reset before loading the new selection" block stays in sync everywhere.
    internal func resetWorkspaceSelection() {
        cancelSync()
        resetAppleAdsSelection()
        localeNotes = []
        selectedLocale = nil
        storeCopyLocales = []
        selectedStoreCopyLocale = nil
        storeCopySourceURL = nil
        storeCopySourceDescription = nil
        remoteNotesByLocale = [:]
        pendingScreenshotReplacement = nil
        resetRemoteScreenshotCounts()
    }

    /// Drop the imported screenshot folder and everything derived from it.
    /// Screenshots belong to one app: keeping app A's folder after switching
    /// to app B would let "Preview All" upload A's images into B. Version
    /// switches within the same app keep the folder.
    internal func resetScreenshotWorkspace() {
        screenshotScanTask?.cancel()
        screenshotScanTask = nil
        // Clearing the request IDs also discards any scan or preview still in
        // flight; their completion handlers check the ID before writing.
        screenshotScanRequestID = nil
        screenshotPreviewRequestID = nil
        isScanningScreenshots = false
        isPreparingScreenshotReplacement = false
        screenshotFolder = nil
        screenshotScan = nil
        selectedScreenshotLocale = nil
        selectedScreenshotAssetId = nil
        screenshotFocusTargetID = nil
        screenshotUploadSummary = nil
        pendingScreenshotReplacement = nil
        screenshotAISharedAssetIDs = []
        screenshotAILocaleOverrides = [:]
        screenshotOrderByGroup = [:]
        screenshotCoverageGroupsCache = nil
        screenshotIssuesCache = nil
        resetRemoteScreenshotCounts()
    }

    /// Bumped every time a dry run finishes. Views observe this to pop the
    /// Sync History sheet so the user can actually see the result.
    var dryRunCompletionTick: Int = 0

    internal func recordSyncRun(
        localeResults: [String: LocaleSyncResult],
        dryRun: Bool,
        kind: SyncKind = .releaseNotes,
        appId: String? = nil,
        versionId: String? = nil
    ) {
        let run = SyncRun(
            id: UUID(),
            appId: appId ?? selectedAppId ?? "",
            versionId: versionId ?? selectedVersionId ?? "",
            startedAt: Date(),
            completedAt: Date(),
            dryRun: dryRun,
            localeResults: localeResults,
            kind: kind
        )
        appendSyncRun(run)
    }

    internal static let syncHistoryPersistKey = "shipnotes.syncHistory.v1"
    internal static let syncHistoryMaxRetained = 100

    /// Insert a run at the head, cap the list at `syncHistoryMaxRetained`,
    /// and write the result to UserDefaults so it survives an app relaunch.
    internal func appendSyncRun(_ run: SyncRun) {
        syncHistory.insert(run, at: 0)
        if syncHistory.count > Self.syncHistoryMaxRetained {
            syncHistory = Array(syncHistory.prefix(Self.syncHistoryMaxRetained))
        }
        persistSyncHistory()
    }

    internal func persistSyncHistory() {
        do {
            let encoder = JSONEncoder()
            // Use ISO 8601 so timestamps are stable, human-readable, and not
            // dependent on the encoder's default (deferred-to-date) strategy.
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(syncHistory)
            defaults.set(data, forKey: Self.syncHistoryPersistKey)
        } catch {
            // Persistence is best-effort; don't surface this to the user.
            // The next run will retry.
        }
    }

    /// Restore previously-persisted sync runs into the in-memory history.
    /// Called from init so the user sees their past runs immediately on launch.
    func loadPersistedSyncHistory() {
        guard let data = defaults.data(forKey: Self.syncHistoryPersistKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Fall back to the default (deferred-to-date) strategy if the payload
        // was written by an older build that didn't use ISO 8601 yet.
        let runs = (try? decoder.decode([SyncRun].self, from: data))
            ?? (try? JSONDecoder().decode([SyncRun].self, from: data))
        guard let runs else { return }
        syncHistory = runs
    }

    func clearSyncHistory() {
        syncHistory = []
        defaults.removeObject(forKey: Self.syncHistoryPersistKey)
    }

}
