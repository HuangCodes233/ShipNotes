import Testing
import Foundation
@testable import ShipNotes

@Suite("ReleaseNotesParser")
struct ReleaseNotesParserTests {
    let parser = ReleaseNotesParser()

    @Test func parsesLocaleMarkdownFolder() throws {
        let folder = try makeTempFolder()
        try "Hello".write(to: folder.appending(path: "en-US.md"), atomically: true, encoding: .utf8)
        try "你好".write(to: folder.appending(path: "zh-Hans.md"), atomically: true, encoding: .utf8)
        try "こんにちは".write(to: folder.appending(path: "ja.md"), atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: folder)
        #expect(parsed.locales["en-US"] == "Hello")
        #expect(parsed.locales["zh-Hans"] == "你好")
        #expect(parsed.locales["ja"] == "こんにちは")
        #expect(parsed.sourceFiles.count == 3)
    }

    @Test func parsesLocaleMarkdownFolderInsideMetadataSubfolder() throws {
        let folder = try makeTempFolder()
        let metadata = folder.appending(path: "AppStore/metadata")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try "Hello".write(to: metadata.appending(path: "en.md"), atomically: true, encoding: .utf8)
        try "你好".write(to: metadata.appending(path: "zh-Hans.md"), atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: folder.appending(path: "AppStore"))
        #expect(parsed.locales["en-US"] == "Hello")
        #expect(parsed.locales["zh-Hans"] == "你好")
        #expect(parsed.sourceDescription.hasSuffix("/AppStore/metadata"))
    }

    @Test func parsesProjectRootByFindingAppStoreMetadataFolder() throws {
        let project = try makeTempFolder()
        let metadata = project.appending(path: "AppStore/metadata")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appending(path: "design"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appending(path: "TiGang.xcodeproj"), withIntermediateDirectories: true)
        try "English notes from project root.".write(
            to: metadata.appending(path: "en.md"),
            atomically: true,
            encoding: .utf8
        )
        try "项目根目录里的中文说明。".write(
            to: metadata.appending(path: "zh-Hans.md"),
            atomically: true,
            encoding: .utf8
        )

        let parsed = try parser.parse(url: project)

        #expect(parsed.locales["en-US"] == "English notes from project root.")
        #expect(parsed.locales["zh-Hans"] == "项目根目录里的中文说明。")
        #expect(parsed.sourceDescription.hasSuffix("/AppStore/metadata"))
    }

    @Test func parsesFastlaneMetadataReleaseNotesFolder() throws {
        let project = try makeTempFolder()
        let enFolder = project.appending(path: "fastlane/metadata/en-US")
        let zhFolder = project.appending(path: "fastlane/metadata/zh-Hans")
        try FileManager.default.createDirectory(at: enFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zhFolder, withIntermediateDirectories: true)

        try "English What's New from Fastlane".write(
            to: enFolder.appending(path: "release_notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "中文更新内容来自 Fastlane".write(
            to: zhFolder.appending(path: "release_notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let parsed = try parser.parse(url: project)
        #expect(parsed.locales["en-US"] == "English What's New from Fastlane")
        #expect(parsed.locales["zh-Hans"] == "中文更新内容来自 Fastlane")
    }

    @Test func appStoreMetadataFolderImportsOnlyWhatsNewSections() throws {
        let folder = try makeTempFolder()
        let metadata = folder.appending(path: "metadata")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)

        let english = """
        # Demo Planner - App Store Metadata (English)

        > Each field matches App Store Connect character limits. Ready to copy-paste.

        ---

        ## 1. App Name
        **Limit: 30 characters**

        ```
        Demo Planner - Daily Tasks
        ```

        ---

        ## 5. Description
        **Limit: 4000 characters**

        ```
        This is the long product description and should never be imported as release notes.
        ```

        ---

        ## 9. What's New (version release notes)
        **First release: "First release"**

        ```
        First release, welcome to Demo Planner

        • Simple task lists
        • Optional reminders for upcoming tasks
        • Calendar check-ins for completed tasks
        • Sort completed and upcoming tasks

        This is synthetic release-note content.
        ```
        """

        let chinese = """
        # 示例计划 - App Store 提交文案

        ## 一、App 名称 (App Name)
        ```
        示例计划 - 每日任务
        ```

        ---

        ## 五、描述 (Description)
        ```
        这是完整产品描述，不应该导入为版本更新说明。
        ```

        ---

        ## 九、What's New (版本更新说明)
        **首次上架填："首次上架"**

        ```
        首次上架，欢迎体验

        • 查看示例任务列表
        • 设置任务提醒
        • 在日历中查看已完成任务
        • 按状态筛选示例任务

        此文案仅用于解析器测试。
        ```
        """

        try english.write(to: metadata.appending(path: "en.md"), atomically: true, encoding: .utf8)
        try chinese.write(to: metadata.appending(path: "zh-Hans.md"), atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: metadata, currentVersion: "1.7.0")
        #expect(parsed.locales["en-US"]?.hasPrefix("First release, welcome") == true)
        #expect(parsed.locales["zh-Hans"]?.hasPrefix("首次上架，欢迎体验") == true)
        #expect(parsed.locales["en-US"]?.contains("long product description") == false)
        #expect(parsed.locales["zh-Hans"]?.contains("完整产品描述") == false)
        #expect(parsed.locales["en-US"]?.contains("App Name") == false)
        #expect(parsed.locales["zh-Hans"]?.contains("App 名称") == false)
        #expect(!parsed.requiresReview)
    }

    @Test func inferVersionFromVersionedFolderName() throws {
        let parent = try makeTempFolder()
        let versioned = parent.appending(path: "1.4.0")
        try FileManager.default.createDirectory(at: versioned, withIntermediateDirectories: true)
        try "Hello".write(to: versioned.appending(path: "en-US.md"), atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: versioned)
        #expect(parsed.version == "1.4.0")
    }

    @Test func parsesYAMLFile() throws {
        let folder = try makeTempFolder()
        let yaml = """
        version: 1.5.0
        locales:
          en-US: |
            Bug fixes.
          zh-Hans: |
            修复问题。
        """
        let url = folder.appending(path: "notes.yaml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)
        #expect(parsed.version == "1.5.0")
        #expect(parsed.locales["en-US"]?.contains("Bug fixes.") == true)
        #expect(parsed.locales["zh-Hans"]?.contains("修复问题。") == true)
    }

    @Test func mapsAliasLocaleCodes() throws {
        let folder = try makeTempFolder()
        try "Hello".write(to: folder.appending(path: "zh-CN.md"), atomically: true, encoding: .utf8)
        try "Bonjour".write(to: folder.appending(path: "fr.md"), atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: folder)
        #expect(parsed.locales["zh-Hans"] == "Hello")
        #expect(parsed.locales["fr-FR"] == "Bonjour")
    }

    @Test func throwsOnEmptyFolder() throws {
        let folder = try makeTempFolder()
        #expect(throws: ReleaseNotesParserError.self) {
            _ = try parser.parse(url: folder)
        }
    }

    @Test func parsesJSONFile() throws {
        let folder = try makeTempFolder()
        let json = """
        {"version": "2.0.0", "locales": {"en-US": "New features.", "ja": "新機能。"}}
        """
        let url = folder.appending(path: "notes.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        let parsed = try parser.parse(url: url)
        #expect(parsed.version == "2.0.0")
        #expect(parsed.locales["en-US"] == "New features.")
        #expect(parsed.locales["ja"] == "新機能。")
    }

    @Test func parsesChangelogFile() throws {
        let folder = try makeTempFolder()
        let md = """
        # Changelog

        ## 1.2.0
        - Added dark mode.
        - Fixed crash on launch.

        ## 1.1.0
        - Initial release.
        """
        let url = folder.appending(path: "CHANGELOG.md")
        try md.write(to: url, atomically: true, encoding: .utf8)
        let parsed = try parser.parse(url: url)
        #expect(parsed.version == "1.2.0")
        #expect(parsed.locales["en-US"]?.contains("Added dark mode") == true)
    }

    @Test func changelogServesTheRequestedVersionAndStripsHeadingDates() throws {
        let folder = try makeTempFolder()
        let md = """
        # Changelog

        ## [Unreleased]
        - Work in progress.

        ## [2.4.0] - 2026-09-01
        ### Added
        - Widgets.

        ## [2.3.0] - 2026-08-01
        ### Fixed
        - Sync crash.

        [2.4.0]: https://example.com/compare/v2.3.0...v2.4.0
        """
        let url = folder.appending(path: "CHANGELOG.md")
        try md.write(to: url, atomically: true, encoding: .utf8)

        let latest = try parser.parse(url: url)
        #expect(latest.version == "2.4.0")
        #expect(latest.locales["en-US"]?.contains("Widgets") == true)
        #expect(latest.locales["en-US"]?.contains("### Added") == true)

        let older = try parser.parse(url: url, currentVersion: "2.3.0")
        #expect(older.version == "2.3.0")
        #expect(older.locales["en-US"]?.contains("Sync crash") == true)
        #expect(older.locales["en-US"]?.contains("Widgets") == false)
        #expect(older.locales["en-US"]?.contains("https://example.com") == false)

        #expect(throws: ReleaseNotesParserError.self) {
            _ = try parser.parse(url: url, currentVersion: "9.9.9")
        }
    }

    @Test func parsesAppStoreMetadataFileExtractingMatchingVersion() throws {
        let folder = try makeTempFolder()
        let md = """
        # App Store Metadata — Deutsch (de)

        ## App Name
        ```
        ExampleTimer - Arbeitszeit
        ```

        ## Beschreibung
        ```
        Eine fiktive Beispiel-App für Timer.
        ```

        ## Was ist neu (What's New)
        ```
        Was ist neu in v2.12.3:

        • Neue Schnellaktionen für heute
        • Wochenübersicht für erfasste Tage

        ---

        Was ist neu in v2.12.2:

        • Tägliche Erinnerungen klingeln nicht mehr am Wochenende

        ---

        Was ist neu in v2.12.0:

        • Frisches Design mit neuem Monats-Ring
        ```

        ## Keywords
        ```
        timer,beispiel,listen
        ```
        """
        let url = folder.appending(path: "de.md")
        try md.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "2.12.2")
        let body = parsed.locales["de-DE"] ?? ""
        #expect(body.contains("Tägliche Erinnerungen"))
        #expect(!body.contains("Schnellaktionen"), "Should not include v2.12.3 content")
        #expect(!body.contains("App Name"), "Should not include other H2 sections")
        #expect(!body.contains("arbeitszeit,stempeluhr"), "Should not include keywords")
        #expect(!body.contains("Was ist neu in v2.12.2"), "Should strip the version header line")
    }

    @Test func metadataFileFallsBackToLatestWhenVersionMissing() throws {
        let folder = try makeTempFolder()
        let md = """
        ## What's New
        ```
        What's New in v3.0.0:

        Latest content.

        ---

        What's New in v2.9.0:

        Older content.
        ```
        """
        let url = folder.appending(path: "en-US.md")
        try md.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "5.0.0")
        let body = parsed.locales["en-US"] ?? ""
        #expect(body.contains("Latest content."))
        #expect(!body.contains("Older content."))
    }

    @Test func metadataFileExtractsFirstReleaseWhatsNewWithoutVersionNumber() throws {
        let folder = try makeTempFolder()
        let md = """
        # Demo Planner - App Store Metadata (English)

        ## 1. App Name
        ```
        Demo Planner - Daily Tasks
        ```

        ## 9. What's New (version release notes)
        **First release: "First release"**

        ```
        First release, welcome to Demo Planner

        • Simple task lists
        • Optional reminders for upcoming tasks
        • Sort completed and upcoming tasks
        ```

        ---

        ## 10. Marketing copy
        Screenshot captions here.
        """
        let url = folder.appending(path: "en.md")
        try md.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "1.7.0")
        let body = parsed.locales["en-US"] ?? ""
        #expect(body.hasPrefix("First release, welcome"))
        #expect(body.contains("Simple task lists"))
        #expect(!body.contains("App Name"))
        #expect(!body.contains("Marketing copy"))
        #expect(!body.contains("First release:"))
        #expect(!parsed.requiresReview)
        #expect((parsed.candidatesByLocale["en-US"] ?? []).count > 1)
        #expect(parsed.candidatesByLocale["en-US"]?.first?.title.contains("What's New") == true)
    }

    @Test func versionHistoryFileExtractsNestedAppStoreWhatsNewLocales() throws {
        let folder = try makeTempFolder()
        let md = """
        # App Store Version History

        ## 1.0.3 (Build 13)

        ### Status

        Implemented locally. Ready for device QA before App Store submission.

        ### App Store What's New

        #### English (en)

        Older English notes.

        ## 1.0.2 (Build 12)

        ### Status

        Implemented locally. Ready for device QA before App Store submission.

        ### Release Focus

        Add a lightweight share/export path after processing.

        ### App Store What's New

        #### Simplified Chinese (zh-Hans)

        新增分享/导出：裁切和增强完成后，可以通过系统分享面板把结果发送到文件、邮件、备忘录或其他 App。

        #### English (en)

        Added Share / Export: after cropping and enhancement, send the result to Files, Mail, Notes, or other apps from the system share sheet.

        #### Japanese (ja)

        共有 / 書き出しを追加しました。裁切と補正が完了した画像を、システム共有シートからファイル、メール、メモ、ほかのアプリへ送れます。

        ### Validation

        - `git diff --check`
        - `build_sim`

        ### Submission Notes

        - App version: `1.0.2`
        - Build number: `12`
        """
        let url = folder.appending(path: "app-store-version-history.md")
        try md.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "1.0.2")
        let english = parsed.locales["en-US"] ?? ""

        #expect(parsed.version == "1.0.2")
        #expect(parsed.locales["zh-Hans"]?.hasPrefix("新增分享/导出") == true)
        #expect(english.hasPrefix("Added Share / Export"))
        #expect(parsed.locales["ja"]?.hasPrefix("共有 / 書き出し") == true)
        #expect(!english.contains("Implemented locally"))
        #expect(!english.contains("Validation"))
        #expect(!english.contains("Build number"))
        #expect(!english.contains("Older English notes"))
        #expect(!parsed.requiresReview)
    }

    @Test func ambiguousMetadataRequiresReviewWhenNoRecommendedFieldExists() throws {
        let folder = try makeTempFolder()
        let md = """
        ## App Name
        ```
        Example App
        ```

        ## Notes
        ```
        Internal notes that might be release notes.
        ```
        """
        let url = folder.appending(path: "en.md")
        try md.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "1.0.0")
        #expect(parsed.requiresReview)
        #expect(parsed.candidatesByLocale["en-US"]?.first?.title == "App Name")
    }

    @Test func folderWithVersionStampedReleaseNotesPicksMatchingFile() throws {
        let folder = try makeTempFolder()
        // Synthesise the user's AppStoreAssets-style folder: many sibling
        // files, only one of which is the release notes for the current version.
        try "irrelevant".write(to: folder.appending(path: "Localization_en.txt"), atomically: true, encoding: .utf8)
        try "irrelevant".write(to: folder.appending(path: "Keywords_v1.9.txt"), atomically: true, encoding: .utf8)
        let dashSeparated = """
        --- 简体中文 ---
        v3.0.2 中文发布说明
        - 新功能

        --- English（美国）---
        v3.0.2 English release notes
        - New feature
        """
        try dashSeparated.write(to: folder.appending(path: "ReleaseNotes_v3.0.2.txt"), atomically: true, encoding: .utf8)
        try "older".write(to: folder.appending(path: "ReleaseNotes_v3.0.1.txt"), atomically: true, encoding: .utf8)
        try "much older".write(to: folder.appending(path: "ReleaseNotes_v2.8.0.txt"), atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: folder, currentVersion: "3.0.2")
        #expect(parsed.locales["zh-Hans"]?.contains("中文发布说明") == true)
        #expect(parsed.locales["en-US"]?.contains("English release notes") == true)
        #expect(parsed.locales["zh-Hans"]?.contains("v3.0.1") != true)
    }

    @Test func folderWithReleaseNotesRejectsMissingSelectedVersion() throws {
        let folder = try makeTempFolder()
        try "v3 body".write(to: folder.appending(path: "ReleaseNotes_v3.0.2.txt"), atomically: true, encoding: .utf8)
        try "v2 body".write(to: folder.appending(path: "ReleaseNotes_v2.8.0.txt"), atomically: true, encoding: .utf8)
        try "irrelevant".write(to: folder.appending(path: "Keywords_v1.9.txt"), atomically: true, encoding: .utf8)

        #expect(throws: ReleaseNotesParserError.self) {
            try parser.parse(url: folder, currentVersion: "99.99.99")
        }
        let parsed = try parser.parse(url: folder)
        #expect(parsed.locales.values.contains { $0.contains("v3 body") })
    }

    @Test func plainReleaseNotesFileIsUsedAsIs() throws {
        let folder = try makeTempFolder()
        let md = """
        • Improved import speed.
        • Fixed a rare crash.
        """
        let url = folder.appending(path: "ja.md")
        try md.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "1.0.0")
        #expect(parsed.locales["ja"]?.contains("Improved import speed") == true)
        #expect(parsed.locales["ja"]?.contains("Fixed a rare crash") == true)
        #expect(!parsed.requiresReview)
        #expect(parsed.candidatesByLocale["ja"]?.count == 1)
    }

    @Test func dashSeparatedReleaseNotesRecognizesNativeHindiAndBahasaIndonesiaHeadings() throws {
        let folder = try makeTempFolder()
        let notes = """
        ========== v3.1.4 Release Notes ==========

        --- Bahasa Indonesia ---
        v3.1.4 Bahasa baru
        - Menambahkan UI app dalam bahasa Thailand, Portugis Brasil, dan Hindi

        --- हिन्दी ---
        v3.1.4 नए भाषा अपडेट
        - Thai, Brazilian Portuguese और Hindi app UI जोड़ा गया

        --- English（美国）---
        v3.1.4 — New localizations
        - Added Thai, Brazilian Portuguese, and Hindi app UI
        """
        let url = folder.appending(path: "ReleaseNotes_v3.1.4.txt")
        try notes.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "3.1.4")

        #expect(parsed.locales["id"]?.contains("Bahasa baru") == true)
        #expect(parsed.locales["hi"]?.contains("नए भाषा अपडेट") == true)
        #expect(parsed.locales["en-US"]?.contains("New localizations") == true)
    }

    private func makeTempFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
