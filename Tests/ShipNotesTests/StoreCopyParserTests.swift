import Foundation
import Testing
@testable import ShipNotes

@Suite("StoreCopyParser")
struct StoreCopyParserTests {
    let parser = StoreCopyParser()

    @Test func parsesMarkdownMetadataFieldsFromLocaleFile() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "en.md")
        let markdown = """
            # Demo App Store Metadata

            ## 1. App Name
            ```
            Demo App
            ```

            ## 5. Description
            **Limit: 4000 characters**

            ```
            A focused app for shipping App Store updates.
            ```

            ## 6. Keywords
            ```
            app store,release,metadata
            ```

            ## 7. Promotional Text
            ```
            Ship a cleaner update today.
            ```

            ## Support URL
            ```
            https://example.com/support
            ```
            """
        try markdown.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)
        let metadata = parsed.locales["en-US"]

        #expect(metadata?.description == "A focused app for shipping App Store updates.")
        #expect(metadata?.keywords == "app store,release,metadata")
        #expect(metadata?.promotionalText == "Ship a cleaner update today.")
        #expect(metadata?.supportURL == "https://example.com/support")
        #expect(metadata?.marketingURL == nil)
    }

    @Test func parsesProjectRootByFindingAppStoreMetadataFolder() throws {
        let project = try makeTempFolder()
        let metadata = project.appending(path: "AppStore/metadata")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try """
        ## Description
        ```
        English description.
        ```
        ## Keywords
        ```
        english,keywords
        ```
        """.write(to: metadata.appending(path: "en.md"), atomically: true, encoding: .utf8)
        try """
        ## 描述
        ```
        中文描述。
        ```
        ## 关键词
        ```
        中文,关键词
        ```
        """.write(to: metadata.appending(path: "zh-Hans.md"), atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: project)

        #expect(parsed.locales["en-US"]?.description == "English description.")
        #expect(parsed.locales["en-US"]?.keywords == "english,keywords")
        #expect(parsed.locales["zh-Hans"]?.description == "中文描述。")
        #expect(parsed.locales["zh-Hans"]?.keywords == "中文,关键词")
        #expect(parsed.sourceDescription.hasSuffix("/AppStore/metadata"))
    }

    @Test func parsesStructuredJSONLocales() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "store-copy.json")
        let json = """
            {
              "locales": {
                "en-US": {
                  "description": "English description.",
                  "keywords": "ship,notes",
                  "promotionalText": "New polish."
                },
                "zh-CN": {
                  "description": "中文描述。",
                  "keywords": "发布,商店"
                }
              }
            }
            """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url)

        #expect(parsed.locales["en-US"]?.description == "English description.")
        #expect(parsed.locales["en-US"]?.promotionalText == "New polish.")
        #expect(parsed.locales["zh-Hans"]?.keywords == "发布,商店")
    }

    @Test func splitsFieldSpecificKeywordFileIntoLocales() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "v1.9 Keywords.txt")
        let text = """
            ========== v1.9 Keywords ==========

            --- 日本語 (ja) --- [99 chars]
            ふりがな,漢字,読み方,JLPT

            --- English (en) --- [100 chars]
            furigana,kanji,hiragana,JLPT

            --- 简体中文 (zh-Hans) --- [98 chars]
            假名,日语,汉字,读音
            """
        try text.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: folder, defaultLocale: "en-AU")

        #expect(parsed.locales["ja"]?.keywords == "ふりがな,漢字,読み方,JLPT")
        #expect(parsed.locales["en-US"]?.keywords == "furigana,kanji,hiragana,JLPT")
        #expect(parsed.locales["zh-Hans"]?.keywords == "假名,日语,汉字,读音")
        #expect(parsed.locales["en-AU"] == nil)
    }

    @Test func parsesSubtitleAndPrivacyPolicyURLFromMarkdownAndYAML() throws {
        let folder = try makeTempFolder()
        let mdURL = folder.appending(path: "en.md")
        let markdown = """
            ## Subtitle
            ```
            Fast, offline Markdown notes
            ```
            ## Description
            ```
            The best app for writing notes on Mac.
            ```
            ## Privacy Policy URL
            ```
            https://example.com/privacy-policy
            ```
            """
        try markdown.write(to: mdURL, atomically: true, encoding: .utf8)
        let parsedMD = try parser.parse(url: mdURL)
        #expect(parsedMD.locales["en-US"]?.subtitle == "Fast, offline Markdown notes")
        #expect(parsedMD.locales["en-US"]?.description == "The best app for writing notes on Mac.")
        #expect(parsedMD.locales["en-US"]?.privacyPolicyURL == "https://example.com/privacy-policy")

        let yamlURL = folder.appending(path: "copy.yaml")
        let yaml = """
            locales:
              zh-Hans:
                subtitle: 简洁高效的发布说明助手
                description: 快速同步多语言发布文案
                privacyPolicyURL: https://example.com/zh/privacy
            """
        try yaml.write(to: yamlURL, atomically: true, encoding: .utf8)
        let parsedYAML = try parser.parse(url: yamlURL)
        #expect(parsedYAML.locales["zh-Hans"]?.subtitle == "简洁高效的发布说明助手")
        #expect(parsedYAML.locales["zh-Hans"]?.privacyPolicyURL == "https://example.com/zh/privacy")
    }

    @Test func parsesFastlaneMetadataDirectoryLayout() throws {
        let root = try makeTempFolder()
        let fastlaneMeta = root.appending(path: "fastlane/metadata")
        let enFolder = fastlaneMeta.appending(path: "en-US")
        let zhFolder = fastlaneMeta.appending(path: "zh-Hans")
        try FileManager.default.createDirectory(at: enFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zhFolder, withIntermediateDirectories: true)

        try "Fastlane Subtitle".write(to: enFolder.appending(path: "subtitle.txt"), atomically: true, encoding: .utf8)
        try "Fastlane Description".write(
            to: enFolder.appending(path: "description.txt"), atomically: true, encoding: .utf8)
        try "fastlane,metadata,app".write(
            to: enFolder.appending(path: "keywords.txt"), atomically: true, encoding: .utf8)
        try "https://example.com/privacy".write(
            to: enFolder.appending(path: "privacy_url.txt"), atomically: true, encoding: .utf8)

        try "中文副标题".write(to: zhFolder.appending(path: "subtitle.txt"), atomically: true, encoding: .utf8)
        try "中文应用描述".write(to: zhFolder.appending(path: "description.txt"), atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: root)
        #expect(parsed.locales["en-US"]?.subtitle == "Fastlane Subtitle")
        #expect(parsed.locales["en-US"]?.description == "Fastlane Description")
        #expect(parsed.locales["en-US"]?.keywords == "fastlane,metadata,app")
        #expect(parsed.locales["en-US"]?.privacyPolicyURL == "https://example.com/privacy")

        #expect(parsed.locales["zh-Hans"]?.subtitle == "中文副标题")
        #expect(parsed.locales["zh-Hans"]?.description == "中文应用描述")
    }

    @Test func folderImportSkipsScreenshotTitleCopyWithoutStoreCopyFields() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "ScreenshotTitleCopy.txt")
        let text = """
            ========== v3.x Screenshot Title Copy ==========

            --- Screenshot 1: Hero / Furigana ---
            日本語: 漢字に瞬時ふりがな
            English: Instant Furigana
            简体中文: 汉字瞬间标音
            """
        try text.write(to: url, atomically: true, encoding: .utf8)

        #expect(throws: StoreCopyParserError.self) {
            _ = try parser.parse(url: folder, defaultLocale: "en-AU")
        }
    }

    private func makeTempFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesStoreCopyParser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
