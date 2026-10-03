import Foundation

@MainActor
extension AppState {
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
            version.looksLikeFirstMarketingVersion
        else {
            return false
        }
        let releasedStates: Set<AppStoreVersionState> = [
            .accepted,
            .pendingAppleRelease,
            .pendingDeveloperRelease,
            .readyForSale,
            .developerRemovedFromSale,
            .removedFromSale,
        ]
        let appVersions = versionsByApp[appId] ?? []
        return !appVersions.contains { candidate in
            candidate.id != version.id && releasedStates.contains(candidate.appStoreState)
        }
    }

    var reviewReadyLocaleNoteCount: Int {
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
}
