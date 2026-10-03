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
        case .prepareForSubmission, .developerRejected, .rejected, .metadataRejected, .waitingForReview,
            .readyForReview:
            return true
        default:
            return false
        }
    }

    var isSubmittedForReview: Bool {
        switch self {
        case .waitingForReview, .waitingForExportCompliance, .inReview, .pendingDeveloperRelease, .pendingAppleRelease,
            .pendingContract, .accepted:
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
