import Testing
@testable import ShipNotes

@Suite("ValidationEngine")
struct ValidationEngineTests {
    let engine = ValidationEngine()

    @Test func emptyTextFlagsError() {
        let issues = engine.validate(text: "   \n\n   ")
        #expect(issues.contains { $0.severity == .error })
    }

    @Test func acceptsNormalReleaseNote() {
        let issues = engine.validate(text: "• Improved import speed.\n• Fixed bugs.")
        #expect(issues.isEmpty)
    }

    @Test func flagsOverCharacterLimit() {
        let text = String(repeating: "x", count: ValidationEngine.whatsNewCharacterLimit + 10)
        let issues = engine.validate(text: text)
        // Message text is localized, so just check there's an error issue and it references the count.
        let limitString = "\(ValidationEngine.whatsNewCharacterLimit + 10)"
        #expect(issues.contains { $0.severity == .error && $0.message.contains(limitString) })
    }

    @Test func detectsBoldMarkdown() {
        #expect(engine.containsMarkdown("This is **bold** text."))
    }

    @Test func detectsHeaderMarkdown() {
        #expect(engine.containsMarkdown("# A header\nbody"))
    }

    @Test func detectsLinkMarkdown() {
        #expect(engine.containsMarkdown("See [docs](https://example.com)."))
    }

    @Test func doesNotFlagPlainBullets() {
        #expect(!engine.containsMarkdown("• Plain bullet item\n• Another one"))
    }

    @Test func stripsCommonMarkdownToPlain() {
        let input = "## Header\n- **Bold** item\n- [link](url) text"
        let stripped = engine.stripMarkdownToPlainText(input)
        #expect(!stripped.contains("##"))
        #expect(!stripped.contains("**"))
        #expect(stripped.contains("• "))
        #expect(stripped.contains("link text"))
    }
}
