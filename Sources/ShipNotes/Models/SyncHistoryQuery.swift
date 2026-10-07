import Foundation

enum SyncHistoryOutcome: String, CaseIterable, Identifiable {
    case all, success, partialFailure, failure, processing

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: L("All results")
        case .success: L("Succeeded")
        case .partialFailure: L("Partially failed")
        case .failure: L("Failed")
        case .processing: L("Processing")
        }
    }

    func matches(_ run: SyncRun) -> Bool {
        switch (self, run.result) {
        case (.all, _), (.success, .success), (.partialFailure, .partialFailure),
            (.failure, .failure), (.processing, .processing):
            true
        default: false
        }
    }
}

struct SyncHistoryQuery {
    var search = ""
    var appId = ""
    var kind = ""
    var outcome: SyncHistoryOutcome = .all

    func filter(_ runs: [SyncRun], apps: [AppRecord], versions: [String: [ReleaseVersion]]) -> [SyncRun] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return runs.filter { run in
            guard appId.isEmpty || run.appId == appId,
                kind.isEmpty || run.resolvedKind.rawValue == kind,
                outcome.matches(run)
            else { return false }
            guard !term.isEmpty else { return true }
            let fields =
                [
                    run.displayAppName(apps: apps), run.displayVersion(versions: versions),
                    run.appId, run.versionId, run.resolvedKind.displayName,
                ] + run.localeResults.keys.sorted()
            return fields.contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }
}

extension SyncRun {
    func displayAppName(apps: [AppRecord]) -> String {
        appName ?? apps.first { $0.id == appId }?.name ?? appId
    }

    func displayVersion(versions: [String: [ReleaseVersion]]) -> String {
        versionString ?? versions[appId]?.first { $0.id == versionId }?.versionString ?? versionId
    }
}

enum SyncHistoryExportFormat {
    case json, csv
}

enum SyncHistoryExport {
    static func data(
        for runs: [SyncRun], format: SyncHistoryExportFormat,
        apps: [AppRecord], versions: [String: [ReleaseVersion]]
    ) throws -> Data {
        let resolved = runs.map { run in
            var copy = run
            copy.appName = run.displayAppName(apps: apps)
            copy.versionString = run.displayVersion(versions: versions)
            return copy
        }
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(resolved)
        case .csv:
            let date = ISO8601DateFormatter()
            var rows = [["started_at", "app", "version", "operation", "mode", "locale", "result", "detail"]]
            for run in resolved {
                for locale in run.localeResults.keys.sorted() {
                    let status: String
                    let detail: String
                    switch run.localeResults[locale] ?? .skipped {
                    case .succeeded: (status, detail) = ("succeeded", "")
                    case .skipped: (status, detail) = ("skipped", "")
                    case .processing: (status, detail) = ("processing", "")
                    case .failed(let message): (status, detail) = ("failed", message)
                    }
                    rows.append([
                        date.string(from: run.startedAt), run.appName ?? run.appId,
                        run.versionString ?? run.versionId, run.resolvedKind.rawValue,
                        run.dryRun ? "dryRun" : "sync", locale, status, detail,
                    ])
                }
            }
            return Data((rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").utf8)
        }
    }

    private static func csvCell(_ text: String) -> String {
        // A spreadsheet should display exported text, including provider errors,
        // rather than interpreting it as a formula.
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = first.map { "=+-@".contains($0) } == true ? "'" + text : text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
