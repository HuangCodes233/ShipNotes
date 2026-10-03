import Foundation

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
