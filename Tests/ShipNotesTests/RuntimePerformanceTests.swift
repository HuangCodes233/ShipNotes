import Foundation
import Testing
@testable import ShipNotes

/// Opt in with SHIPNOTES_BENCHMARKS=1 swift test -c release --filter RuntimePerformanceTests.
/// Reports timings without machine-dependent pass/fail thresholds.
@Suite("Runtime performance", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["SHIPNOTES_BENCHMARKS"] == "1"))
struct RuntimePerformanceTests {
    @Test func diffSummaryWhileEditing() {
        let lines = (0..<400).map { "Line \($0)" }
        let old = lines.joined(separator: "\n")
        var edited = lines
        edited[200] = "Edited line"
        let new = edited.joined(separator: "\n")
        let engine = DiffEngine()
        measure("diff-summary-100-edits") {
            var checksum = 0
            for _ in 0..<100 {
                let summary = engine.summary(old: old, new: new)
                checksum += summary.added + summary.removed + summary.unchanged
            }
            #expect(checksum == 40_100)
        }
    }

    @Test func appStoreDateParsing() {
        let strings = [
            "2026-05-19T18:01:23Z", "2026-05-19T18:01:23.456Z",
            "2026-05-19T18:01:23+00:00", "2026-05-19T18:01:23.456+00:00"
        ]
        measure("date-parse-500-values") {
            var parsed = 0
            for index in 0..<500 {
                if AppStoreConnectClient.parseAppStoreConnectDate(strings[index % strings.count]) != nil {
                    parsed += 1
                }
            }
            #expect(parsed == 500)
        }
    }

    @MainActor @Test func screenshotCoverageReads() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        let locales = ["en-US", "en-AU", "en-GB", "en-CA", "fr-FR", "fr-CA",
                       "es-ES", "es-MX", "pt-BR", "pt-PT", "ja", "ko"]
        state.localeNotes = locales.map {
            LocaleNote(locale: $0, remoteLocalizationId: nil, localText: "Ready",
                       remoteText: "Ready", status: .noChange, diffSummary: nil)
        }
        let root = URL(fileURLWithPath: "/tmp/ShipNotes-performance-fixtures")
        let assets = locales.flatMap { locale in
            (0..<10).map { index in
                ScreenshotAsset(
                    url: root.appending(path: "\(locale)/\(index).png"),
                    relativePath: "\(locale)/\(index).png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: locale, deviceSlot: .iPhone69, status: .ready,
                    contentHash: "\(locale)-\(index)"
                )
            }
        }
        state.screenshotScan = ScreenshotScan(inputRoot: root, root: root,
                                             sourceKind: .directFolder, assets: assets, skippedCount: 0)
        measure("screenshot-coverage-cold-120-assets") {
            state.screenshotCoverageGroupsCache = nil
            state.screenshotIssuesCache = nil
            #expect(state.screenshotCoverageGroups.count == locales.count)
        }
        // Exercise the getters used by ScreenshotWorkspaceView, not an
        // aggregate helper that has no production callers.
        measure("screenshot-ui-cache-10-reads") {
            var checksum = 0
            var missing = 0
            for _ in 0..<10 {
                let groups = state.screenshotCoverageGroups
                let requirements = state.missingRequirementsByLocale
                checksum += groups.count + groups.reduce(0) { $0 + $1.assets.count }
                checksum += requirements.count + state.visibleScreenshotSlots.count
                checksum += state.screenshotBlockingIssueCount + state.screenshotWarningCount
                missing += requirements.values.reduce(0) { $0 + $1.count }
            }
            #expect(checksum == 1_460)
            #expect(missing == 0)
        }
    }

    private func measure(_ label: String, operation: () -> Void) {
        operation() // Warm the code and any intentionally reusable resources.
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            operation()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        let median = samples.sorted()[samples.count / 2]
        print("BENCHMARK \(label): median_ms=\(String(format: "%.3f", median)) samples_ms=\(samples)")
    }
}
