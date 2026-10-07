import Foundation

@MainActor
protocol WorkspaceDraftStoring {
    func load() throws -> [WorkspaceDraft]
    func save(_ drafts: [WorkspaceDraft]) throws
}

@MainActor
final class InMemoryWorkspaceDraftStore: WorkspaceDraftStoring {
    var drafts: [WorkspaceDraft] = []

    func load() throws -> [WorkspaceDraft] { drafts }
    func save(_ drafts: [WorkspaceDraft]) throws { self.drafts = drafts }
}

@MainActor
struct FileWorkspaceDraftStore: WorkspaceDraftStoring {
    let fileURL: URL

    /// Explicit directories keep tests and previews away from user documents.
    /// Packaged apps use their own bundle domain, including private builds.
    init(directory: URL? = nil, applicationIdentifier: String? = nil) {
        if let directory {
            fileURL = directory.appendingPathComponent("workspace-drafts-v1.json")
        } else {
            let identifier = applicationIdentifier ?? Bundle.main.bundleIdentifier ?? "org.shipnotes.app"
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            fileURL = support.appendingPathComponent(identifier, isDirectory: true)
                .appendingPathComponent("WorkspaceDrafts", isDirectory: true)
                .appendingPathComponent("workspace-drafts-v1.json")
        }
    }

    func load() throws -> [WorkspaceDraft] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(WorkspaceDraftDocument.self, from: Data(contentsOf: fileURL))
        guard document.schemaVersion == 1 else { throw WorkspaceDraftStoreError.unsupportedSchema }
        return document.drafts
    }

    func save(_ drafts: [WorkspaceDraft]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(WorkspaceDraftDocument(drafts: drafts))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A failed write leaves the previous complete document in place.
        try data.write(to: fileURL, options: .atomic)
    }
}

enum WorkspaceDraftStoreError: LocalizedError {
    case unsupportedSchema

    var errorDescription: String? {
        L("This workspace draft file was created by a newer version of ShipNotes.")
    }
}
