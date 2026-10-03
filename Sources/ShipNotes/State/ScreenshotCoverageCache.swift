import Foundation

struct ScreenshotCoverageGroupsCacheKey: Hashable {
    let locales: [String]
    // Value snapshots share collection storage until it changes. Avoid rebuilding
    // fingerprints and sorting overrides on every cached UI read, and include all
    // asset fields so rescans also refresh dimensions and URLs.
    let assets: [ScreenshotAsset]
    let localeOverrides: [String: String]
    let sharedAssetIDs: Set<String>
}

struct ScreenshotCoverageGroupsCache {
    let key: ScreenshotCoverageGroupsCacheKey
    let groups: [ScreenshotLocaleGroup]
    /// Canonical locale of every scanned asset (`nil` = unassigned), resolved
    /// once per rebuild. Path-based locale resolution is the expensive part of
    /// coverage, and toolbar/AI-matching reads used to redo it per render.
    let localeByAssetID: [String: String?]
}

struct ScreenshotIssuesCacheKey: Hashable {
    let coverageKey: ScreenshotCoverageGroupsCacheKey
    let requiredGroups: [ScreenshotSlotRequirement]
}

struct ScreenshotIssuesCache {
    let key: ScreenshotIssuesCacheKey
    let issues: [ScreenshotIssue]
    let blockingIssueCount: Int
    let warningCount: Int
    let missingRequirementsByLocale: [String: [ScreenshotSlotRequirement]]
    let visibleScreenshotSlots: [ScreenshotDeviceSlot]
    let aiClassificationCandidates: [ScreenshotAsset]
}
