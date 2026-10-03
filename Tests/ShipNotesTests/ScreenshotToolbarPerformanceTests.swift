import Foundation
import Testing
@testable import ShipNotes

/// Opt in with SHIPNOTES_BENCHMARKS=1 swift test -c release --filter ScreenshotToolbarPerformanceTests.
/// Measures the getters the screenshot toolbar reads on every redraw.
@Suite(
    "Screenshot toolbar performance", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SHIPNOTES_BENCHMARKS"] == "1"))
@MainActor
struct ScreenshotToolbarPerformanceTests {
    @Test func toolbarReadsWithVisionAIConfigured() {
        let service = MockASCService()
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            visionAIService: MockScreenshotVisionAIService(),
            appStoreService: service,
            defaults: makeTestDefaults()
        )
        state.apps = [AppRecord(id: "app-1", name: "Demo", bundleId: "x", platform: "iOS", iconSystemName: "app")]
        state.versionsByApp["app-1"] = [
            ReleaseVersion(
                id: "v-1", appId: "app-1", versionString: "1.0", platform: "iOS", appStoreState: .prepareForSubmission)
        ]
        state.selectedAppId = "app-1"
        state.selectedVersionId = "v-1"
        state.isUsingMockData = false

        let locales = LocaleMapper.appStoreLocales
        state.localeNotes = locales.map {
            LocaleNote(
                locale: $0, remoteLocalizationId: "loc-\($0)", localText: "Ready",
                remoteText: "Ready", status: .noChange, diffSummary: nil)
        }
        let root = URL(fileURLWithPath: "/tmp/ShipNotes-toolbar-fixtures")
        let assets = locales.flatMap { locale in
            (0..<9).map { index in
                ScreenshotAsset(
                    url: root.appending(path: "\(locale)/iPhone 6.9 screen \(index).png"),
                    relativePath: "\(locale)/iPhone 6.9 screen \(index).png",
                    size: ScreenshotPixelSize(width: 1320, height: 2868),
                    locale: locale, deviceSlot: .iPhone69, status: .ready,
                    contentHash: nil
                )
            }
        }
        state.screenshotScan = ScreenshotScan(
            inputRoot: root, root: root,
            sourceKind: .directFolder, assets: assets, skippedCount: 0)
        state.selectedScreenshotLocale = "en-US"

        measure("screenshot-toolbar-10-redraws-\(assets.count)-assets") {
            var enabled = 0
            for _ in 0..<10 {
                if state.canClassifyScreenshotsWithAI { enabled += 1 }
                _ = state.screenshotAIClassificationHelp
                if state.canUploadSelectedScreenshots { enabled += 1 }
                _ = state.screenshotSelectedPreviewDisabledReason
                if state.canUploadAllScreenshots { enabled += 1 }
                _ = state.screenshotAllPreviewDisabledReason
            }
            #expect(enabled == 20)
        }
    }

    private func measure(_ label: String, operation: () -> Void) {
        operation()
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
