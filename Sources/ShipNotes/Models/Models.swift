import Foundation

struct Account: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var issuerId: String
    var keyId: String
    var privateKeyReference: String
    var createdAt: Date
    var lastUsedAt: Date
}

struct AppRecord: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var bundleId: String
    var platform: String
    var iconSystemName: String
    var iconURL: URL? = nil
}

enum AppStoreVersionState: String, CaseIterable, Hashable, Sendable {
    case accepted = "ACCEPTED"
    case prepareForSubmission = "PREPARE_FOR_SUBMISSION"
    case developerRejected = "DEVELOPER_REJECTED"
    case invalidBinary = "INVALID_BINARY"
    case rejected = "REJECTED"
    case metadataRejected = "METADATA_REJECTED"
    case pendingAppleRelease = "PENDING_APPLE_RELEASE"
    case pendingContract = "PENDING_CONTRACT"
    case waitingForReview = "WAITING_FOR_REVIEW"
    case waitingForExportCompliance = "WAITING_FOR_EXPORT_COMPLIANCE"
    case inReview = "IN_REVIEW"
    case pendingDeveloperRelease = "PENDING_DEVELOPER_RELEASE"
    case preorderReadyForSale = "PREORDER_READY_FOR_SALE"
    case readyForReview = "READY_FOR_REVIEW"
    case readyForSale = "READY_FOR_SALE"
    case processingForAppStore = "PROCESSING_FOR_APP_STORE"
    case developerRemovedFromSale = "DEVELOPER_REMOVED_FROM_SALE"
    case removedFromSale = "REMOVED_FROM_SALE"
    case replacedWithNewVersion = "REPLACED_WITH_NEW_VERSION"
    case notApplicable = "NOT_APPLICABLE"

    init(apiValue: String?) {
        guard let apiValue, let state = AppStoreVersionState(rawValue: apiValue) else {
            self = .notApplicable
            return
        }
        self = state
    }

    var isEditable: Bool {
        switch self {
        case .prepareForSubmission, .developerRejected, .rejected, .metadataRejected, .waitingForReview, .readyForReview:
            return true
        default:
            return false
        }
    }

    var isSubmittedForReview: Bool {
        switch self {
        case .waitingForReview, .waitingForExportCompliance, .inReview, .pendingDeveloperRelease, .pendingAppleRelease, .pendingContract, .accepted:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .accepted: L("Accepted")
        case .prepareForSubmission: L("Prepare for Submission")
        case .developerRejected: L("Developer Rejected")
        case .invalidBinary: L("Invalid Binary")
        case .rejected: L("Rejected")
        case .metadataRejected: L("Metadata Rejected")
        case .pendingAppleRelease: L("Pending Apple Release")
        case .pendingContract: L("Pending Contract")
        case .waitingForReview: L("Waiting for Review")
        case .waitingForExportCompliance: L("Waiting for Export Compliance")
        case .inReview: L("In Review")
        case .pendingDeveloperRelease: L("Pending Developer Release")
        case .preorderReadyForSale: L("Preorder Ready for Sale")
        case .readyForReview: L("Ready for Review")
        case .readyForSale: L("Ready for Sale")
        case .processingForAppStore: L("Processing")
        case .developerRemovedFromSale: L("Removed from Sale")
        case .removedFromSale: L("Removed from Sale")
        case .replacedWithNewVersion: L("Replaced with New Version")
        case .notApplicable: L("Not Applicable")
        }
    }
}

struct ReleaseVersion: Identifiable, Hashable, Sendable {
    let id: String
    let appId: String
    var versionString: String
    var platform: String
    var appStoreState: AppStoreVersionState
    var createdDate: Date?

    var canEditMetadata: Bool { appStoreState.isEditable }

    var looksLikeFirstMarketingVersion: Bool {
        Self.looksLikeFirstMarketingVersion(versionString)
    }

    static func looksLikeFirstMarketingVersion(_ versionString: String) -> Bool {
        var normalized = versionString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("v") {
            normalized.removeFirst()
        }
        let pieces = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.count <= 3 else { return false }
        guard let major = Int(pieces[0]), major == 1 else { return false }
        return pieces.dropFirst().allSatisfy { Int($0) == 0 }
    }
}

struct RemoteScreenshot: Identifiable, Hashable, Sendable {
    let id: String
    var fileName: String
    var fileSize: Int?
    var imageURL: URL?
    var width: Int?
    var height: Int?
}

struct RemoteScreenshotSet: Identifiable, Hashable, Sendable {
    let id: String
    var localizationId: String
    var displayType: String
    var slot: ScreenshotDeviceSlot?
    var screenshots: [RemoteScreenshot]
}

struct ScreenshotReplacementSlotPlan: Identifiable, Hashable, Sendable {
    var id: String { slot.id }
    var slot: ScreenshotDeviceSlot
    var remoteScreenshots: [RemoteScreenshot]
    var localAssets: [ScreenshotAsset]

    var replacesRemote: Bool { !localAssets.isEmpty }
}

struct ScreenshotReplacementLocalePlan: Identifiable, Hashable, Sendable {
    var id: String { locale }
    var locale: String
    var localizationId: String?
    var slots: [ScreenshotReplacementSlotPlan]

    var replacingSlots: [ScreenshotReplacementSlotPlan] {
        slots.filter(\.replacesRemote)
    }
}

struct ScreenshotReplacementPlan: Identifiable, Hashable, Sendable {
    let id = UUID()
    var locales: [ScreenshotReplacementLocalePlan]
    /// Selection the preview was built for. The upload targets these IDs, not
    /// whatever is selected when a long multi-locale upload reaches a locale.
    var appId: String? = nil
    var versionId: String? = nil

    var localeCount: Int { locales.count }
    var slotCount: Int { locales.reduce(0) { $0 + $1.replacingSlots.count } }
    var remoteDeleteCount: Int {
        locales.reduce(0) { total, locale in
            total + locale.replacingSlots.reduce(0) { $0 + $1.remoteScreenshots.count }
        }
    }
    var localUploadCount: Int {
        locales.reduce(0) { total, locale in
            total + locale.replacingSlots.reduce(0) { $0 + $1.localAssets.count }
        }
    }
}

enum LocaleStatus: Hashable, Sendable, Comparable {
    case ready
    case needsReview
    case missing
    case overLimit
    case invalid
    case noChange
    case failed(String)
    case syncing
    case synced

    var displayName: String {
        switch self {
        case .ready: L("Ready")
        case .needsReview: L("Needs Review")
        case .missing: L("Missing")
        case .overLimit: L("Over Limit")
        case .invalid: L("Invalid")
        case .noChange: L("No Change")
        case .failed: L("Failed")
        case .syncing: L("Syncing")
        case .synced: L("Synced")
        }
    }

    var sortPriority: Int {
        switch self {
        case .failed: 0
        case .overLimit: 1
        case .invalid: 2
        case .missing: 3
        case .needsReview: 4
        case .ready: 5
        case .noChange: 6
        case .syncing: 7
        case .synced: 8
        }
    }

    static func < (lhs: LocaleStatus, rhs: LocaleStatus) -> Bool {
        // Sort by priority first. For two `.failed` cases (same priority) we
        // compare the message so that `<` agrees with `==`/`Hashable` — without
        // this tiebreak, `.failed("a")` and `.failed("b")` would each be
        // `!(<)` of the other yet compare unequal, violating Comparable.
        if lhs.sortPriority != rhs.sortPriority {
            return lhs.sortPriority < rhs.sortPriority
        }
        switch (lhs, rhs) {
        case let (.failed(l), .failed(r)):
            return l < r
        default:
            return false
        }
    }
}

struct DiffSummary: Hashable, Sendable {
    var added: Int
    var removed: Int
    var unchanged: Int

    var hasChanges: Bool { added > 0 || removed > 0 }
}

struct LocaleNote: Identifiable, Hashable, Sendable {
    var id: String { locale }
    let locale: String
    var localPath: URL?
    var remoteLocalizationId: String?
    var localText: String
    var remoteText: String?
    var status: LocaleStatus
    var diffSummary: DiffSummary?
    var validationIssues: [ValidationIssue] = []

    var length: Int { localText.count }
}

enum StoreCopyField: String, CaseIterable, Identifiable, Hashable, Sendable {
    case subtitle
    case description
    case keywords
    case promotionalText
    case supportURL
    case marketingURL
    case privacyPolicyURL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtitle: L("Subtitle")
        case .description: L("Description")
        case .keywords: L("Keywords")
        case .promotionalText: L("Promotional Text")
        case .supportURL: L("Support URL")
        case .marketingURL: L("Marketing URL")
        case .privacyPolicyURL: L("Privacy Policy URL")
        }
    }

    var limit: Int? {
        switch self {
        case .subtitle: 30
        case .description: 4000
        case .keywords: 100
        case .promotionalText: 170
        case .supportURL, .marketingURL, .privacyPolicyURL: nil
        }
    }

    var isURLField: Bool {
        switch self {
        case .supportURL, .marketingURL, .privacyPolicyURL: true
        case .subtitle, .description, .keywords, .promotionalText: false
        }
    }

    var isVersionLocalizationField: Bool {
        switch self {
        case .description, .keywords, .promotionalText, .supportURL, .marketingURL: true
        // Subtitle and privacyPolicyURL live on the app-info level, not the version
        // localization — it can't be written through this endpoint.
        case .subtitle, .privacyPolicyURL: false
        }
    }
}

struct StoreMetadataFields: Hashable, Sendable, Codable {
    var subtitle: String
    var description: String
    var keywords: String
    var promotionalText: String
    var supportURL: String
    var marketingURL: String
    var privacyPolicyURL: String

    init(
        subtitle: String = "",
        description: String = "",
        keywords: String = "",
        promotionalText: String = "",
        supportURL: String = "",
        marketingURL: String = "",
        privacyPolicyURL: String = ""
    ) {
        self.subtitle = subtitle
        self.description = description
        self.keywords = keywords
        self.promotionalText = promotionalText
        self.supportURL = supportURL
        self.marketingURL = marketingURL
        self.privacyPolicyURL = privacyPolicyURL
    }

    static let empty = StoreMetadataFields()

    var isEmpty: Bool {
        StoreCopyField.allCases.allSatisfy {
            value(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func value(for field: StoreCopyField) -> String {
        switch field {
        case .subtitle: subtitle
        case .description: description
        case .keywords: keywords
        case .promotionalText: promotionalText
        case .supportURL: supportURL
        case .marketingURL: marketingURL
        case .privacyPolicyURL: privacyPolicyURL
        }
    }

    mutating func setValue(_ value: String, for field: StoreCopyField) {
        switch field {
        case .subtitle: subtitle = value
        case .description: description = value
        case .keywords: keywords = value
        case .promotionalText: promotionalText = value
        case .supportURL: supportURL = value
        case .marketingURL: marketingURL = value
        case .privacyPolicyURL: privacyPolicyURL = value
        }
    }
}

struct StoreCopyIssue: Hashable, Identifiable, Sendable {
    var id: Self { self }
    let field: StoreCopyField
    let severity: ValidationIssue.Severity
    let message: String
}

struct StoreCopyLocale: Identifiable, Hashable, Sendable {
    var id: String { locale }
    let locale: String
    var remoteLocalizationId: String?
    var localMetadata: StoreMetadataFields
    var remoteMetadata: StoreMetadataFields?
    var status: LocaleStatus
    var changedFieldCount: Int
    var validationIssues: [StoreCopyIssue] = []

    var issueCount: Int { validationIssues.count }
}

/// What a sync run pushed. Optional + defaulted so runs persisted before this
/// field existed decode cleanly (missing → release notes).
enum SyncKind: String, Hashable, Sendable, Codable {
    case releaseNotes
    case storeCopy
    case screenshots

    var displayName: String {
        switch self {
        case .releaseNotes: L("Release Notes")
        case .storeCopy: L("Store Copy")
        case .screenshots: L("Screenshots")
        }
    }
}

struct SyncRun: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let appId: String
    let versionId: String
    let startedAt: Date
    var completedAt: Date?
    var dryRun: Bool
    var localeResults: [String: LocaleSyncResult]
    // Optional with a default so old persisted JSON (no "kind") still decodes.
    var kind: SyncKind? = nil

    var resolvedKind: SyncKind { kind ?? .releaseNotes }

    enum Result: Hashable, Sendable {
        case success
        case partialFailure
        case failure(String)
    }

    var result: Result {
        let failed = localeResults.values.filter { if case .failed = $0 { true } else { false } }
        if failed.isEmpty { return .success }
        if failed.count == localeResults.count { return .failure(failed.first.flatMap { if case .failed(let m) = $0 { m } else { nil } } ?? "All failed") }
        return .partialFailure
    }
}

enum LocaleSyncResult: Hashable, Sendable, Codable {
    case skipped
    case succeeded
    case failed(String)
}

/// One uploaded build, as returned by `GET /v1/builds`. The `id` is what
/// App Store Connect uses to attach the build to a version via
/// `PATCH /v1/appStoreVersions/{id}/relationships/build`.
struct Build: Identifiable, Hashable, Sendable, Codable {
    let id: String
    /// CFBundleVersion — the build number string (e.g., "123" or "1.8.0.4").
    let buildNumber: String
    /// CFBundleShortVersionString — the marketing version (e.g., "1.8.0"). May
    /// be nil if not returned by the API for some reason.
    let marketingVersion: String?
    /// Platform reported by the related prerelease version, when available.
    var platform: String? = nil
    let uploadedDate: Date?
    let expirationDate: Date?
    let processingState: ProcessingState

    enum ProcessingState: String, Hashable, Sendable, Codable {
        case processing = "PROCESSING"
        case failed = "FAILED"
        case invalid = "INVALID"
        case valid = "VALID"
        case unknown = "UNKNOWN"

        init(apiValue: String?) {
            guard let v = apiValue, let s = ProcessingState(rawValue: v) else {
                self = .unknown
                return
            }
            self = s
        }

        var displayName: String {
            switch self {
            case .processing: L("build.state.processing")
            case .failed: L("build.state.failed")
            case .invalid: L("build.state.invalid")
            case .valid: L("build.state.valid")
            case .unknown: L("build.state.unknown")
            }
        }

        /// Only VALID builds can be attached to an App Store version.
        var canBeAttached: Bool { self == .valid }
    }
}


struct ScreenshotPreviewControlsState: Equatable, Sendable {
    let selectedDisabledReason: String?
    let allDisabledReason: String?
}
