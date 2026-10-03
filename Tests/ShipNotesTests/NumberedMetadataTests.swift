import Foundation
import Testing
@testable import ShipNotes

/// Synthetic numbered metadata sections exercise extraction of What's New
/// without importing app names, descriptions, keywords, or later tables.
@Suite("NumberedMetadata")
struct NumberedMetadataTests {
    private let parser = ReleaseNotesParser()

    @Test func numberedMetadataExtractsOnlyWhatsNewBody() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "en.md")
        try numberedMetadata.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "1.7.0")
        let body = parsed.locales["en-US"] ?? ""

        // Expect ONLY the "First release..." What's New body.
        #expect(body.contains("First release, welcome to Demo Planner"))
        #expect(body.contains("Calendar check-ins"))

        // Expect NONE of the other H2 sections.
        #expect(!body.contains("App Store Metadata"), "Should drop H1 intro")
        #expect(!body.contains("App Name"), "Should drop App Name section")
        #expect(!body.contains("Demo Planner - Daily Tasks"), "Should drop App Name value")
        #expect(!body.contains("Organize everyday tasks"), "Should drop Subtitle")
        #expect(!body.contains("Promotional Text"), "Should drop Promotional Text")
        #expect(!body.contains("planner,tasks,calendar"), "Should drop Keywords")
        #expect(!body.contains("Plan Your Next Task"), "Should drop Description")
        #expect(!body.contains("Marketing copy"), "Should drop sections after What's New")
        #expect(!body.contains("Common rejection pitfalls"), "Should drop late tables")

        // Char count should be in the ~250-400 range, not 7000+.
        #expect(body.count < 500, "Expected ~300 chars, got \(body.count)")
    }

    @Test func numberedMetadataHasRecommendedCandidateSoNoPreviewSheet() throws {
        let folder = try makeTempFolder()
        let url = folder.appending(path: "en.md")
        try numberedMetadata.write(to: url, atomically: true, encoding: .utf8)

        let parsed = try parser.parse(url: url, currentVersion: "1.7.0")
        let candidates = parsed.candidatesByLocale["en-US"] ?? []

        // At least one .high (Recommended) candidate exists → app applies directly,
        // no Import Preview sheet is shown.
        #expect(
            candidates.contains { $0.confidence == .high },
            "Expected at least one Recommended candidate; got titles: \(candidates.map(\.title))")
        #expect(!parsed.requiresReview, "Should NOT require review when a Recommended candidate exists")
    }

    private func makeTempFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "ShipNotesMetadataTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // Synthetic metadata fixture; all product copy is fictional.
    private let numberedMetadata = """
        # Demo Planner - App Store Metadata (English)

        > Each field matches App Store Connect character limits. Ready to copy-paste.

        ---

        ## 1. App Name
        **Limit: 30 characters**

        ```
        Demo Planner - Daily Tasks
        ```
        (25 chars)

        ### Alternatives
        ```
        Demo Planner: Task Lists
        ```

        ---

        ## 2. Subtitle
        **Limit: 30 characters**

        ```
        Organize everyday tasks
        ```

        ---

        ## 4. Keywords
        **Limit: 100 characters, comma-separated, NO spaces**

        ```
        planner,tasks,calendar,lists
        ```

        ---

        ## 5. Description
        **Limit: 4000 characters**

        ```
        Demo Planner — Plan Your Next Task

        A fictional planner used only in parser tests.
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

        ---

        ## 10. Marketing copy (App Preview / Screenshot captions)
        **Five-screenshot set:**

        | Screenshot | Caption |
        |------------|---------|
        | 01_home | **View your sample tasks** |

        ---

        ## 13. Common rejection pitfalls (English market)

        | Risk | Mitigation |
        |------|------------|
        | Missing screenshot | Attach a synthetic screenshot |

        """
}
