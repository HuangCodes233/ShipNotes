import Foundation
import Testing
@testable import ShipNotes

@Suite("Sync history search and export")
struct SyncHistoryExportTests {
    private func run(kind: SyncKind = .releaseNotes, result: LocaleSyncResult = .succeeded) -> SyncRun {
        SyncRun(
            id: UUID(), appId: "sample-app", versionId: "sample-version", startedAt: Date(timeIntervalSince1970: 0),
            dryRun: false, localeResults: ["en-US": result], kind: kind, appName: "Sample App", versionString: "2.0")
    }

    @Test func filtersCombineWithSnapshotSearchWithoutLoadedApps() {
        let success = run()
        let failure = run(kind: .screenshots, result: .failed("Synthetic failure"))
        let processing = run(kind: .screenshots, result: .processing)
        let query = SyncHistoryQuery(
            search: "sample app", appId: "sample-app", kind: "screenshots", outcome: .processing)
        #expect(query.filter([success, failure, processing], apps: [], versions: [:]).map(\.id) == [processing.id])
        #expect(SyncHistoryQuery(search: "en-us").filter([success], apps: [], versions: [:]).count == 1)
    }

    @Test func jsonExportRoundtripsSnapshotAndProcessingResults() throws {
        let record = run(result: .processing)
        let data = try SyncHistoryExport.data(for: [record], format: .json, apps: [], versions: [:])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode([SyncRun].self, from: data)
        #expect(restored == [record])
        #expect(restored.first?.result == .processing)
    }

    @Test func csvQuotesErrorsAndEscapesSpreadsheetFormulas() throws {
        var record = run(result: .failed("=synthetic,\"quoted\"\nmessage"))
        record.appName = "+Sample"
        let data = try SyncHistoryExport.data(for: [record], format: .csv, apps: [], versions: [:])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"'+Sample\""))
        #expect(text.contains("\"'=synthetic,\"\"quoted\"\"\nmessage\""))
        #expect(text.contains("1970-01-01T00:00:00Z"))
    }

    @Test func oldHistoryWithoutSnapshotsStillDecodes() throws {
        let data = Data(
            """
            [{"id":"00000000-0000-0000-0000-000000000001","appId":"sample-app","versionId":"sample-version",
            "startedAt":"1970-01-01T00:00:00Z","dryRun":false,"localeResults":{"en-US":{"succeeded":{}}}}]
            """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode([SyncRun].self, from: data)
        #expect(restored.first?.appName == nil)
        #expect(restored.first?.resolvedKind == .releaseNotes)
        #expect(restored.first?.displayAppName(apps: []) == "sample-app")
    }
}
