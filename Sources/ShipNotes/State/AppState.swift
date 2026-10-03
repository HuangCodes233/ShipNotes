import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

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
    @ObservationIgnored var screenshotUploadRequestID: UUID?
    /// Identity of the latest replacement-preview request. A preview that
    /// finishes after a newer request (or a selection change) is discarded.
    @ObservationIgnored var screenshotPreviewRequestID: UUID?
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

    @ObservationIgnored let parser = ReleaseNotesParser()
    @ObservationIgnored let storeCopyParser = StoreCopyParser()
    @ObservationIgnored let diff = DiffEngine()
    @ObservationIgnored let validator = ValidationEngine()
    @ObservationIgnored let fileWatcher = FileWatcher()
    @ObservationIgnored let credentialStore: any AppStoreConnectCredentialStoring
    @ObservationIgnored let aiKeychainStore: any AIKeychainStoring
    @ObservationIgnored var aiService: any AIService {
        didSet { aiServiceRevision &+= 1 }
    }
    @ObservationIgnored var visionAIService: any ScreenshotVisionAIService {
        didSet { aiServiceRevision &+= 1 }
    }
    /// Observed stand-in for the unobservable service values above, so views
    /// reading `isAIConfigured` update as soon as a key is saved or removed.
    var aiServiceRevision = 0
    @ObservationIgnored var appStoreService: (any AppStoreConnectServicing)?
    @ObservationIgnored let appleAdsCredentialStore: any AppleAdsCredentialStoring
    @ObservationIgnored var appleAdsService: (any AppleAdsServicing)?
    @ObservationIgnored var remoteNotesByLocale: [String: RemoteLocaleNote] = [:]
    @ObservationIgnored var screenshotScanRequestID: UUID?
    @ObservationIgnored var screenshotScanTask: Task<Void, Never>?
    @ObservationIgnored var syncTask: Task<Void, Never>?
    @ObservationIgnored var syncGeneration: UUID = UUID()
    @ObservationIgnored var syncActivityToken: UUID?
    @ObservationIgnored var folderLoadRequestID: UUID?
    @ObservationIgnored var versionCreationContextRequestID: UUID?
    @ObservationIgnored var screenshotCoverageGroupsCache: ScreenshotCoverageGroupsCache?

    @ObservationIgnored var screenshotIssuesCache: ScreenshotIssuesCache?
    @ObservationIgnored var remoteScreenshotCountsTask: Task<Void, Never>?
    @ObservationIgnored var remoteScreenshotCountsVersionId: String?
    @ObservationIgnored var remoteScreenshotCountsRequestID: UUID?
    /// Backing store for persisted settings (sync history, AI call count,
    /// screenshot overrides, strip-markdown flag). Injectable so tests can use
    /// an ephemeral `UserDefaults` suite instead of polluting `.standard`.
    @ObservationIgnored let defaults: UserDefaults

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

    var localeNotesStats: LocaleNotesStats {
        LocaleNotesStats.from(localeNotes)
    }

    var storeCopyStats: StoreCopyStats {
        StoreCopyStats.from(storeCopyLocales)
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

    /// Clear all per-workspace selection state and loaded content. Called from
    /// several app/version switching paths in AppState+AppStoreConnect, so the
    /// "reset before loading the new selection" block stays in sync everywhere.
    func resetWorkspaceSelection() {
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
    func resetScreenshotWorkspace() {
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

}
