import Foundation
import Testing
@testable import ShipNotes

@Suite("Screenshot coverage cache")
@MainActor
struct ScreenshotCoverageCacheTests {
    private let root = URL(fileURLWithPath: "/tmp/ShipNotes-coverage-fixtures")

    @Test func sharingAndLocaleOverridesRefreshCachedCoverage() {
        let state = makeState(locales: ["en-US", "en-CA", "ja"])
        let image = asset(path: "screen.png", locale: "en-US")
        state.screenshotScan = scan([image])
        let missingPhone: [ScreenshotSlotRequirement] = [.oneOf([.iPhone69, .iPhone65])]
        #expect(state.missingRequirementsByLocale == ["en-US": [], "en-CA": missingPhone, "ja": missingPhone])
        #expect(state.screenshotAssets(locale: "en-CA", slot: .iPhone69).isEmpty)

        state.screenshotAISharedAssetIDs.insert(image.id)
        #expect(state.missingRequirementsByLocale == ["en-US": [], "en-CA": [], "ja": missingPhone])
        #expect(state.missingScreenshotRequirements(locale: "en-CA").isEmpty)
        #expect(state.screenshotAssets(locale: "en-CA", slot: .iPhone69).map(\.id) == [image.id])

        state.screenshotAISharedAssetIDs.remove(image.id)
        #expect(state.missingRequirementsByLocale == ["en-US": [], "en-CA": missingPhone, "ja": missingPhone])
        #expect(state.missingScreenshotRequirements(locale: "en-CA").count == 1)

        state.screenshotAILocaleOverrides[image.id] = "ja"
        #expect(state.missingRequirementsByLocale == ["en-US": missingPhone, "en-CA": missingPhone, "ja": []])
        #expect(state.screenshotAssets(locale: "en-US", slot: .iPhone69).isEmpty)
        #expect(state.missingScreenshotRequirements(locale: "ja").isEmpty)
        #expect(state.screenshotAssets(locale: "ja", slot: .iPhone69).map(\.id) == [image.id])

        state.localeNotes.removeAll { $0.locale != "ja" }
        #expect(state.screenshotCoverageGroups.map(\.locale) == ["ja"])
        #expect(state.missingRequirementsByLocale == ["ja": []])
    }

    @Test func requirementChangesRefreshMissingCountsWithoutChangingAssets() {
        let state = makeState(locales: ["en-US"])
        state.selectedAppId = "test-app"
        state.screenshotScan = scan([asset(path: "en-US/phone.png", locale: "en-US")])
        #expect(state.missingRequirementsByLocale == ["en-US": []])
        #expect(state.missingScreenshotRequirements(locale: "en-US").isEmpty)

        state.screenshotIPadSupportOverrides["test-app"] = .required
        #expect(state.missingRequirementsByLocale == ["en-US": [.exact(.iPad13)]])
        #expect(state.missingScreenshotRequirements(locale: "en-US") == [.exact(.iPad13)])

        state.screenshotIPadSupportOverrides["test-app"] = .ignored
        #expect(state.missingRequirementsByLocale == ["en-US": []])
        #expect(state.missingScreenshotRequirements(locale: "en-US").isEmpty)
    }

    @Test func rescanRefreshesDimensionsAndRemovingScanClearsCoverage() {
        let state = makeState(locales: ["en-US"])
        let original = asset(path: "en-US/unsupported.png", locale: "en-US", width: 101)
        state.screenshotScan = scan([original])
        #expect(state.effectiveScreenshotAssets(locale: "en-US").first?.size.width == 101)
        #expect(state.screenshotBlockingIssueCount == 2)

        let replacement = asset(path: "en-US/unsupported.png", locale: "en-US", width: 202)
        state.screenshotScan = scan([replacement])
        #expect(state.effectiveScreenshotAssets(locale: "en-US").first?.size.width == 202)
        #expect(state.screenshotIssues.contains { $0.detail.contains("202 x 2868") })

        state.screenshotScan = nil
        #expect(state.screenshotCoverageGroups.isEmpty)
        #expect(state.missingRequirementsByLocale.isEmpty)
        #expect(state.screenshotIssues.isEmpty)
        #expect(state.screenshotAssets(locale: "en-US", slot: .iPhone69).isEmpty)
    }

    @Test func undisplayedAndUnassignedLocalesKeepTheirQuerySemantics() {
        let state = makeState(locales: ["ja"])
        let image = asset(path: "screen.png", locale: nil)
        state.screenshotScan = scan([image])
        #expect(state.screenshotCoverageGroups.contains { $0.isUnassigned && $0.assets == [image] })
        #expect(state.effectiveScreenshotAssets(locale: ScreenshotScan.unassignedLocaleDisplayName).isEmpty)
        #expect(state.missingScreenshotRequirements(locale: ScreenshotScan.unassignedLocaleDisplayName).isEmpty)
        #expect(state.missingScreenshotRequirements(locale: "ko") == [.oneOf([.iPhone69, .iPhone65])])
        #expect(state.missingRequirementsByLocale == ["ja": [.oneOf([.iPhone69, .iPhone65])]])
    }

    private func makeState(locales: [String]) -> AppState {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        state.localeNotes = locales.map {
            LocaleNote(
                locale: $0, remoteLocalizationId: nil, localText: "Ready",
                remoteText: "Ready", status: .noChange, diffSummary: nil)
        }
        return state
    }

    private func asset(path: String, locale: String?, width: Int = 1320) -> ScreenshotAsset {
        ScreenshotAsset(
            url: root.appending(path: path), relativePath: path,
            size: ScreenshotPixelSize(width: width, height: 2868), locale: locale,
            deviceSlot: width == 1320 ? .iPhone69 : nil,
            status: width == 1320 ? .ready : .unsupportedSize, contentHash: nil)
    }

    private func scan(_ assets: [ScreenshotAsset]) -> ScreenshotScan {
        ScreenshotScan(inputRoot: root, root: root, sourceKind: .directFolder, assets: assets, skippedCount: 0)
    }
}
