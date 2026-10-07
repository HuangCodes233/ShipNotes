import Foundation

/// A hash of the non-secret account identifiers scopes each workspace. No
/// credential payload, API key, or private-key reference belongs in a draft.
struct WorkspaceDraftKey: Hashable, Codable, Sendable {
    let accountID: String
    let appID: String
    let versionID: String
}

struct WorkspaceDraftText: Equatable, Codable, Sendable {
    var text: String
    var remoteBaseline: String?
    var sourceBaseline: String
    var wasEdited: Bool
}

struct WorkspaceDraft: Codable, Sendable {
    let key: WorkspaceDraftKey
    var savedAt: Date
    var releaseNotes: [String: WorkspaceDraftText] = [:]
    var storeCopy: [String: [String: WorkspaceDraftText]] = [:]
    var releaseSourceURL: URL?
    var storeCopySourceURL: URL?
    var screenshotFolder: URL?
    var selectedLocale: String?
    var selectedStoreCopyLocale: String?
    var selectedScreenshotLocale: String?
    var workspaceMode: String
    var screenshotAssetHashes: [String: String] = [:]
    var screenshotLocaleOverrides: [String: String] = [:]
    var screenshotSharedAssetIDs: Set<String> = []
    var screenshotOrderByGroup: [String: [String]] = [:]
}

struct WorkspaceDraftDocument: Codable, Sendable {
    var schemaVersion = 1
    var drafts: [WorkspaceDraft] = []
}
