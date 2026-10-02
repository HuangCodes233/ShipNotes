import Testing
import Foundation
@testable import ShipNotes

/// Verifies that AnthropicService can recover when an Anthropic-compatible
/// proxy ignores the forced `tool_use` instruction and returns the structured
/// payload as plain text instead — common with non-Claude models routed
/// through the Anthropic protocol (LiteLLM, OneAPI, third-party gateways).
@Suite("Anthropic proxy text fallback")
struct AnthropicTextFallbackTests {
    @Test func parsesRawJSONInTextBlockWhenToolUseMissing() async throws {
        let raw = """
        {"content":[{"type":"text","text":"{\\"locales\\":{\\"en-US\\":\\"• AI extracted body\\"}}"}]}
        """
        let response = try JSONSerialization.jsonObject(with: raw.data(using: .utf8)!) as! [String: Any]
        let json = try AnthropicService.testHook_extractToolInput(response, expectedName: "submit_release_notes")
        let locales = json["locales"] as? [String: String] ?? [:]
        #expect(locales["en-US"] == "• AI extracted body")
    }

    @Test func parsesJSONInFencedCodeBlock() async throws {
        // Some proxies prefix the JSON with a Markdown ```json fence.
        let raw = """
        {"content":[{"type":"text","text":"```json\\n{\\"translated_text\\":\\"翻译后的内容\\"}\\n```"}]}
        """
        let response = try JSONSerialization.jsonObject(with: raw.data(using: .utf8)!) as! [String: Any]
        let json = try AnthropicService.testHook_extractToolInput(response, expectedName: "submit_translation")
        #expect(json["translated_text"] as? String == "翻译后的内容")
    }

    @Test func extractsJSONFromProseSurroundedText() async throws {
        // Some proxies wrap the JSON in conversational prose.
        let raw = """
        {"content":[{"type":"text","text":"Sure, here's the translation:\\n\\n{\\"translated_text\\":\\"翻译后的内容\\"}\\n\\nLet me know if you need anything else."}]}
        """
        let response = try JSONSerialization.jsonObject(with: raw.data(using: .utf8)!) as! [String: Any]
        let json = try AnthropicService.testHook_extractToolInput(response, expectedName: "submit_translation")
        #expect(json["translated_text"] as? String == "翻译后的内容")
    }

    @Test func realToolUseStillPreferredWhenPresent() async throws {
        let raw = """
        {"content":[
            {"type":"text","text":"{\\"locales\\":{\\"en-US\\":\\"WRONG fallback\\"}}"},
            {"type":"tool_use","name":"submit_release_notes","input":{"locales":{"en-US":"CORRECT tool_use"}}}
        ]}
        """
        let response = try JSONSerialization.jsonObject(with: raw.data(using: .utf8)!) as! [String: Any]
        let json = try AnthropicService.testHook_extractToolInput(response, expectedName: "submit_release_notes")
        let locales = json["locales"] as? [String: String] ?? [:]
        #expect(locales["en-US"] == "CORRECT tool_use")
    }
}
