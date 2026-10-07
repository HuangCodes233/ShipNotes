import Foundation

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
    var appName: String? = nil
    var versionString: String? = nil

    var resolvedKind: SyncKind { kind ?? .releaseNotes }

    enum Result: Hashable, Sendable {
        case success
        case processing
        case partialFailure
        case failure(String)
    }

    var result: Result {
        let failed = localeResults.values.filter { if case .failed = $0 { true } else { false } }
        if failed.isEmpty {
            return localeResults.values.contains(.processing) ? .processing : .success
        }
        if failed.count == localeResults.count {
            return .failure(failed.first.flatMap { if case .failed(let m) = $0 { m } else { nil } } ?? "All failed")
        }
        return .partialFailure
    }
}

enum LocaleSyncResult: Hashable, Sendable, Codable {
    case skipped
    case succeeded
    /// Bytes uploaded; Apple's asset processing has not yet been confirmed.
    case processing
    case failed(String)
}
