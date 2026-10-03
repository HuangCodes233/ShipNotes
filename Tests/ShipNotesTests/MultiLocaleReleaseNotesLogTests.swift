import Foundation
import Testing
@testable import ShipNotes

/// Tests the multi-locale release-notes-log format: a single .md file that
/// contains ALL versions × ALL languages, with `## v1.7.0` for versions and
/// `### 🇨🇳 简体中文` / `### 🇺🇸 English` etc. for languages.
@Suite("MultiLocaleReleaseNotesLog")
struct MultiLocaleReleaseNotesLogTests {
    private let parser = ReleaseNotesParser()

    @Test func extractsAllLocalesForSelectedVersion() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "release_notes.md")
        try demoLog.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "1.7.0")

        // All 6 locales mapped from flag emojis present in the v1.7.0 section
        #expect(parsed.locales["zh-Hans"]?.contains("呼吸动画") == true)
        #expect(parsed.locales["en-US"]?.contains("Visual Refresh") == true)
        #expect(parsed.locales["ja"]?.contains("ビジュアル刷新") == true)
        #expect(parsed.locales["ko"]?.contains("비주얼 리프레시") == true)
        #expect(parsed.locales["zh-Hant"]?.contains("視覺升級") == true)
        #expect(parsed.locales["es-ES"]?.contains("Renovación visual") == true)
        #expect(parsed.locales.count == 6, "Expected 6 locales, got \(parsed.locales.keys.sorted())")
    }

    @Test func doesNotIncludeOtherVersionBodies() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "release_notes.md")
        try demoLog.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "1.7.0")

        // None of v1.6 / v1.5 / v1.0 content should appear in any v1.7 body.
        for (locale, body) in parsed.locales {
            #expect(!body.contains("成就系统"), "locale \(locale) should not contain v1.6 zh-Hans body")
            #expect(!body.contains("Achievement"), "locale \(locale) should not contain v1.6 en-US body")
            #expect(!body.contains("Statistics"), "locale \(locale) should not contain v1.5 en-US body")
            #expect(!body.contains("First release"), "locale \(locale) should not contain v1.0 body")
        }
    }

    @Test func picksLatestVersionWhenSelectedDoesNotMatch() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "release_notes.md")
        try demoLog.write(to: url, atomically: true, encoding: .utf8)

        // 99.9.9 is not in the file — should pick the first version section (v1.7.0).
        let parsed = try parser.parse(url: url, currentVersion: "99.9.9")
        #expect(parsed.locales["en-US"]?.contains("Visual Refresh") == true)
    }

    @Test func bodyExcludesH3HeadingAndFlagEmoji() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "release_notes.md")
        try demoLog.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "1.7.0")
        let enUSBody = parsed.locales["en-US"] ?? ""
        #expect(!enUSBody.contains("🇺🇸"), "Body should not contain flag emoji")
        #expect(!enUSBody.contains("###"), "Body should not contain heading marker")
    }

    @Test func matchesShortVersionToFullVersionInFile() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "release_notes.md")
        try demoLog.write(to: url, atomically: true, encoding: .utf8)

        // User selects "1.6" (no patch) — should match "v1.6.0" in the file.
        let parsed = try parser.parse(url: url, currentVersion: "1.6")
        #expect(parsed.locales["en-US"]?.contains("Achievements") == true)
    }

    @Test func appliesDirectlyWithoutPreviewSheet() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "release_notes.md")
        try demoLog.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "1.7.0")
        // Log format is unambiguous — no Import Preview should be required.
        #expect(!parsed.requiresReview)
    }

    private func makeTempFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesLogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // Synthetic multilingual fixture with version and locale headings.
    private let demoLog = """
        # Release Notes — Demo Planner

        Fictional release notes for parser regression tests.

        ---

        ## v1.7.0 — Visual Refresh

        ### 🇨🇳 简体中文
        ```
        v1.7 — 视觉升级

        • 示例图标加入呼吸动画
        • 更新任务卡片样式
        ```

        ### 🇺🇸 English
        ```
        v1.7 — Visual Refresh

        • Added animation to the sample icon
        • Updated task card styling
        ```

        ### 🇯🇵 日本語
        ```
        v1.7 — ビジュアル刷新

        • サンプルアイコンにアニメーションを追加
        • タスクカードの表示を更新
        ```

        ### 🇰🇷 한국어
        ```
        v1.7 — 비주얼 리프레시

        • 예제 아이콘에 애니메이션 추가
        • 작업 카드 표시 업데이트
        ```

        ### 🇹🇼 繁體中文
        ```
        v1.7 — 視覺升級

        • 範例圖示加入動畫
        • 更新任務卡片樣式
        ```

        ### 🇪🇸 Español
        ```
        v1.7 — Renovación visual

        • Animación para el icono de ejemplo
        • Nuevo estilo para las tarjetas de tareas
        ```

        ---

        ## v1.6.0 — Achievements

        ### 🇨🇳 简体中文
        ```
        成就系统：完成示例任务后显示徽章。
        ```

        ### 🇺🇸 English
        ```
        Achievements: badges for completed sample tasks.
        ```

        ---

        ## v1.5.0 — Statistics

        ### 🇺🇸 English
        ```
        Statistics: a summary of completed sample tasks.
        ```

        ---

        ## v1.0.0 — First release

        ### 🇺🇸 English
        ```
        First release, welcome to Demo Planner.
        ```
        """
}
