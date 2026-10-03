import Foundation

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
