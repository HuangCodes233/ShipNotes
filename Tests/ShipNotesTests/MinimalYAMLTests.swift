import Testing
@testable import ShipNotes

@Suite("MinimalYAML")
struct MinimalYAMLTests {
    let yaml = MinimalYAML()

    @Test func parsesScalarKeys() throws {
        let result = try yaml.parse("version: 1.4.0\nname: ShipNotes")
        #expect(result["version"] as? String == "1.4.0")
        #expect(result["name"] as? String == "ShipNotes")
    }

    @Test func parsesNestedMap() throws {
        let text = """
        locales:
          en-US: hello
          zh-Hans: 你好
        """
        let result = try yaml.parse(text)
        let locales = result["locales"] as? [String: Any]
        #expect(locales?["en-US"] as? String == "hello")
        #expect(locales?["zh-Hans"] as? String == "你好")
    }

    @Test func parsesBlockScalar() throws {
        let text = """
        version: 1.4.0
        locales:
          en-US: |
            Line one
            Line two
          zh-Hans: |
            第一行
            第二行
        """
        let result = try yaml.parse(text)
        let locales = result["locales"] as? [String: Any]
        let en = locales?["en-US"] as? String
        #expect(en?.contains("Line one") == true)
        #expect(en?.contains("Line two") == true)
        let zh = locales?["zh-Hans"] as? String
        #expect(zh?.contains("第一行") == true)
    }

    @Test func unquotes() throws {
        let result = try yaml.parse(#"name: "ShipNotes""#)
        #expect(result["name"] as? String == "ShipNotes")
    }

    @Test func skipsCommentsAndDocumentMarkers() throws {
        let text = """
        # Release notes for 1.4.0
        ---
        version: 1.4.0 # the upcoming release
        locales:
          # English is the primary locale
          en-US: hello
        ...
        """
        let result = try yaml.parse(text)
        #expect(result["version"] as? String == "1.4.0")
        let locales = result["locales"] as? [String: Any]
        #expect(locales?["en-US"] as? String == "hello")
    }
}
