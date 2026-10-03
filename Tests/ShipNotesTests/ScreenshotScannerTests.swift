import Foundation
import Testing
#if canImport(AppKit)
import AppKit
#endif
@testable import ShipNotes

@Suite("ScreenshotScanner")
struct ScreenshotScannerTests {
    @Test func scansLocaleFoldersAndClassifiesDeviceSlots() throws {
        let folder = try makeTempFolder()
        let english = folder.appending(path: "en-US")
        let chinese = folder.appending(path: "zh-Hans")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chinese, withIntermediateDirectories: true)
        try writePNG(width: 1320, height: 2868, to: english.appending(path: "01-home.png"))
        try writePNG(width: 100, height: 100, to: chinese.appending(path: "bad-size.png"))

        let scan = try ScreenshotScanner().scan(url: folder)

        #expect(scan.assets.count == 2)
        #expect(scan.readyCount == 1)
        #expect(scan.unsupportedCount == 1)
        #expect(scan.assets.first { $0.locale == "en-US" }?.deviceSlot == .iPhone69)
        #expect(scan.assets.first { $0.locale == "zh-Hans" }?.status == .unsupportedSize)
    }

    @Test func localeFolderWinsOverLanguageLikeWordsInFileName() throws {
        let folder = try makeTempFolder()
        let english = folder.appending(path: "en-US")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        try writePNG(width: 1320, height: 2868, to: english.appending(path: "iPhone 6.9 no-ads 01.png"))

        let scan = try ScreenshotScanner().scan(url: folder)

        #expect(scan.assets.first?.locale == "en-US")
    }

    @Test func detectsTraditionalChineseBeforeGenericChineseLanguageToken() throws {
        let folder = try makeTempFolder()
        let traditional = folder.appending(path: "zh-Hant/6.9inch")
        try FileManager.default.createDirectory(at: traditional, withIntermediateDirectories: true)
        try writePNG(width: 1320, height: 2868, to: traditional.appending(path: "zh-Hant_6.9inch_01.png"))

        let scan = try ScreenshotScanner().scan(url: folder)

        #expect(scan.assets.count == 1)
        #expect(scan.assets.first?.locale == "zh-Hant")
        #expect(scan.localeGroups.map(\.locale) == ["zh-Hant"])
    }

    @Test func skipsProjectBundlesDuringRecursiveScan() throws {
        let folder = try makeTempFolder()
        let screenshots = folder.appending(path: "screenshots/en-US")
        let projectBundle = folder.appending(path: "Demo.xcodeproj/en-US")
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectBundle, withIntermediateDirectories: true)
        try writePNG(width: 1320, height: 2868, to: screenshots.appending(path: "real.png"))
        try writePNG(width: 1320, height: 2868, to: projectBundle.appending(path: "ignored.png"))

        let scan = try ScreenshotScanner().scan(url: folder)

        #expect(scan.assets.count == 1)
        #expect(scan.assets.first?.relativePath == "screenshots/en-US/real.png")
    }

    @Test func projectRootDiscoversAppStoreScreenshotsFolder() throws {
        let project = try makeTempFolder()
        let screenshots = project.appending(path: "AppStore/screenshots/en-US")
        let otherImages = project.appending(path: "output")
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherImages, withIntermediateDirectories: true)
        try writePNG(width: 1320, height: 2868, to: screenshots.appending(path: "01-home.png"))
        try writePNG(width: 100, height: 100, to: otherImages.appending(path: "scratch.png"))

        let scan = try ScreenshotScanner().scan(url: project)

        #expect(scan.inputRoot == project)
        #expect(scan.root.path.hasSuffix("AppStore/screenshots"))
        #expect(scan.sourceKind == .discoveredFolder)
        #expect(scan.assets.count == 1)
        #expect(scan.assets.first?.relativePath == "en-US/01-home.png")
    }

    @Test func projectRootPrefersUploadScreenshotsOverRawAndPreviewAssets() throws {
        let project = try makeTempFolder()
        let screenshotsRoot = project.appending(path: "AppStoreAssets/screenshots")
        let raw = screenshotsRoot.appending(path: "raw")
        let final = screenshotsRoot.appending(path: "final")
        let upload = screenshotsRoot.appending(path: "upload/iphone-6.5")
        for folder in [raw, final, upload] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try writePNG(width: 1206, height: 2622, to: raw.appending(path: "01-home-full.png"))
        try writePNG(width: 1242, height: 2688, to: final.appending(path: "01-home.png"))
        try writePNG(width: 1242, height: 2688, to: upload.appending(path: "01-home.png"))

        let scan = try ScreenshotScanner().scan(url: project)

        #expect(scan.root.path.hasSuffix("AppStoreAssets/screenshots/upload"))
        #expect(scan.assets.count == 1)
        #expect(scan.unsupportedCount == 0)
        #expect(scan.assets.first?.relativePath == "iphone-6.5/01-home.png")
    }

    @Test func onlyFilesThatCouldBeDuplicatesAreHashed() throws {
        let folder = try makeTempFolder()
        let english = folder.appending(path: "en-US")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        try writePNG(width: 1320, height: 2868, to: english.appending(path: "01-home.png"))
        try writePNG(width: 1320, height: 2868, to: english.appending(path: "02-copy.png"))
        try writePNG(width: 1242, height: 2688, to: english.appending(path: "03-other-size.png"))

        let scan = try ScreenshotScanner().scan(url: folder)
        let hashes = Dictionary(uniqueKeysWithValues: scan.assets.map { ($0.url.lastPathComponent, $0.contentHash) })

        #expect(hashes["01-home.png"] ?? nil != nil)
        #expect(hashes["01-home.png"] == hashes["02-copy.png"])
        // A file with a unique (locale, slot, byte size) can't be a duplicate.
        #expect(hashes["03-other-size.png"] ?? "unexpected" == nil)
    }

    @Test func cancelledScanStopsWithCancellationError() async throws {
        let folder = try makeTempFolder()
        let english = folder.appending(path: "en-US")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        try writePNG(width: 1320, height: 2868, to: english.appending(path: "01-home.png"))

        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ScreenshotScanner().scan(url: folder)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test func reportsMissingUnsupportedAndDuplicateIssues() throws {
        let folder = try makeTempFolder()
        let english = folder.appending(path: "en-US")
        let chinese = folder.appending(path: "zh-Hans")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chinese, withIntermediateDirectories: true)
        try writePNG(width: 1320, height: 2868, to: english.appending(path: "01-home.png"))
        try writePNG(width: 1320, height: 2868, to: english.appending(path: "02-home-copy.png"))
        try writePNG(width: 100, height: 100, to: chinese.appending(path: "bad-size.png"))

        let scan = try ScreenshotScanner().scan(url: folder)
        let issues = scan.issues(expectedSlots: [.iPhone65, .iPad13])

        #expect(issues.contains { $0.title == expectedLocalized("Missing required screenshot size") })
        #expect(issues.contains { $0.title == expectedLocalized("Unsupported screenshot size") })
        #expect(issues.contains { $0.title == expectedLocalized("Possible duplicate screenshots") })
        #expect(issues.filter { $0.severity == .error }.count >= 2)
    }

    @Test func iphoneRequirementAcceptsEitherSixNineOrSixFive() throws {
        let folder = try makeTempFolder()
        let english = folder.appending(path: "en-US")
        let chinese = folder.appending(path: "zh-Hans")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chinese, withIntermediateDirectories: true)
        try writePNG(width: 1320, height: 2868, to: english.appending(path: "iphone-69.png"))
        try writePNG(width: 1242, height: 2688, to: chinese.appending(path: "iphone-65.png"))

        let scan = try ScreenshotScanner().scan(url: folder)
        let requirement = ScreenshotSlotRequirement.oneOf([.iPhone69, .iPhone65])

        #expect(scan.missingRequirements(for: "en-US", requiredGroups: [requirement]).isEmpty)
        #expect(scan.missingRequirements(for: "zh-Hans", requiredGroups: [requirement]).isEmpty)
        #expect(
            !scan.issues(requiredGroups: [requirement]).contains {
                $0.title == expectedLocalized("Missing required screenshot size")
            })
    }

    @Test func detectsExpoTabletSupportFromProjectAncestor() throws {
        let project = try makeTempFolder()
        let screenshots = project.appending(path: "app-store-metadata/generated-screenshots")
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        try writeText(
            #"{"expo":{"ios":{"supportsTablet":false}}}"#,
            to: project.appending(path: "app.json")
        )

        let detection = ScreenshotIPadSupportDetector.detect(from: screenshots)

        #expect(detection.supportsIPad == false)
    }

    @Test func xcodeProjectUsesMainApplicationTargetForIPadDetection() throws {
        let project = try makeTempFolder()
        let screenshots = project.appending(path: "screenshots")
        let xcodeProject = project.appending(path: "TiGang.xcodeproj")
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xcodeProject, withIntermediateDirectories: true)
        try writeText(
            """
            // !$*UTF8*$!
            {
                objects = {
                    APP000000000000000000001 /* TiGang */ = {
                        isa = PBXNativeTarget;
                        buildConfigurationList = APPLIST0000000000000001 /* Build configuration list for PBXNativeTarget "TiGang" */;
                        productType = "com.apple.product-type.application";
                    };
                    WIDGET00000000000000001 /* TiGangWidgetExtension */ = {
                        isa = PBXNativeTarget;
                        buildConfigurationList = WIDGETLIST000000000001 /* Build configuration list for PBXNativeTarget "TiGangWidgetExtension" */;
                        productType = "com.apple.product-type.app-extension";
                    };
                    APPLIST0000000000000001 /* Build configuration list for PBXNativeTarget "TiGang" */ = {
                        isa = XCConfigurationList;
                        buildConfigurations = (
                            APPDEBUG00000000000001 /* Debug */,
                            APPREL0000000000000001 /* Release */,
                        );
                    };
                    WIDGETLIST000000000001 /* Build configuration list for PBXNativeTarget "TiGangWidgetExtension" */ = {
                        isa = XCConfigurationList;
                        buildConfigurations = (
                            WIDGETDEBUG000000001 /* Debug */,
                            WIDGETREL00000000001 /* Release */,
                        );
                    };
                    APPDEBUG00000000000001 /* Debug */ = {
                        isa = XCBuildConfiguration;
                        buildSettings = {
                            TARGETED_DEVICE_FAMILY = 1;
                        };
                        name = Debug;
                    };
                    APPREL0000000000000001 /* Release */ = {
                        isa = XCBuildConfiguration;
                        buildSettings = {
                            TARGETED_DEVICE_FAMILY = 1;
                        };
                        name = Release;
                    };
                    WIDGETDEBUG000000001 /* Debug */ = {
                        isa = XCBuildConfiguration;
                        buildSettings = {
                            TARGETED_DEVICE_FAMILY = "1,2";
                        };
                        name = Debug;
                    };
                    WIDGETREL00000000001 /* Release */ = {
                        isa = XCBuildConfiguration;
                        buildSettings = {
                            TARGETED_DEVICE_FAMILY = "1,2";
                        };
                        name = Release;
                    };
                };
            }
            """,
            to: xcodeProject.appending(path: "project.pbxproj")
        )

        let detection = ScreenshotIPadSupportDetector.detect(from: screenshots)

        #expect(detection.supportsIPad == false)
    }

    @Test func unassignedScreenshotsDoNotCreateMissingSlotErrors() throws {
        let folder = try makeTempFolder()
        try writePNG(width: 1320, height: 2868, to: folder.appending(path: "01-home.png"))

        let scan = try ScreenshotScanner().scan(url: folder)
        let group = try #require(scan.localeGroups.first)
        let issues = scan.issues(expectedSlots: [.iPhone65, .iPad13])

        #expect(group.isUnassigned)
        #expect(issues.contains { $0.title == expectedLocalized("Locale not detected") && $0.severity == .warning })
        #expect(
            !issues.contains {
                $0.title == expectedLocalized("Missing required screenshot size") && $0.locale == group.locale
            })
    }

    private func makeTempFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesScreenshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writeText(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writePNG(width: Int, height: Int, to url: URL) throws {
        #if canImport(AppKit)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let data = rep.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        #else
        throw CocoaError(.fileWriteUnknown)
        #endif
    }
}
