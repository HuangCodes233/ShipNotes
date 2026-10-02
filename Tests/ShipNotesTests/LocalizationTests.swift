import Testing
import Foundation
@testable import ShipNotes

@Suite("Localization", .serialized)
struct LocalizationTests {
    /// Resolve strings with a language preference scoped to this task
    /// (`nil` = no preference, follow the system). Swapping the process-wide
    /// `activeDefaults` instead changed the language `L()` returned to every
    /// suite running in parallel, which made unrelated assertions on English
    /// messages flaky.
    private func withLanguage(_ code: String?, _ body: () -> Void) {
        LanguageManager.$languageOverride.withValue(code ?? "") {
            body()
        }
    }

    @Test func englishKeyRoundtripsWhenNoOverride() {
        withLanguage(nil) {
            #expect(L("Apps") == "Apps")
            #expect(L("Sync Selected") == "Sync Selected")
        }
    }

    @Test func simplifiedChineseResolves() {
        withLanguage("zh-Hans") {
            #expect(L("Apps") == "应用")
            #expect(L("Sync Selected") == "同步所选")
            #expect(L("Settings") == "设置")
        }
    }

    @Test func japaneseResolves() {
        withLanguage("ja") {
            #expect(L("Apps") == "アプリ")
            #expect(L("Sync Selected") == "選択を同期")
            #expect(L("Settings") == "設定")
        }
    }

    @Test func formatVariantInterpolates() {
        withLanguage("zh-Hans") {
            let value = L("%d ready", 3)
            #expect(value.contains("3"))
            #expect(value.contains("就绪"))
        }
    }

    @Test func twoArgPositionalFormatWorks() {
        withLanguage(nil) {
            let value = L("Exceeds App Store limit of %1$d characters (currently %2$d)", 4000, 4010)
            #expect(value.contains("4000"), "Got: \(value)")
            #expect(value.contains("4010"), "Got: \(value)")
        }
    }

    @Test func unknownLanguageFallsBackToEnglish() {
        withLanguage("xx-YY") {
            #expect(L("Apps") == "Apps")
        }
    }

    @Test func languageOptionsCoverThreeLanguagesPlusSystem() {
        let codes = LanguageOption.allCases.map(\.rawValue)
        #expect(codes.contains(""))
        #expect(codes.contains("en"))
        #expect(codes.contains("zh-Hans"))
        #expect(codes.contains("ja"))
    }

    // MARK: - Key completeness validation

    /// Locate the project root by walking up from #filePath until Package.swift is found.
    private func projectRoot() -> URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: dir.appending(path: "Package.swift").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// Collect all .swift file URLs under Sources/.
    private func swiftSourceFiles(root: URL) -> [URL] {
        let sourcesDir = root.appending(path: "Sources")
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { item in
            let url = item as! URL
            guard url.pathExtension == "swift" else { return nil }
            return url
        }
    }

    /// Extract all localization keys used via L("...") calls in source code.
    /// Handles escaped quotes inside keys and multiline calls.
    private func extractUsedKeys(from files: [URL]) -> Set<String> {
        // Matches L("..." where the key may contain escaped quotes.
        // The regex captures the first string literal argument to L().
        let pattern = #"L\(\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        var keys = Set<String>()
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, options: [], range: range) {
                guard match.numberOfRanges >= 2,
                      let keyRange = Range(match.range(at: 1), in: content) else { continue }
                let rawKey = String(content[keyRange])
                // Unescape \" and \\ that appear in Swift string literals.
                let unescaped = rawKey
                    .replacingOccurrences(of: "\\\\", with: "\\")
                    .replacingOccurrences(of: "\\\"", with: "\"")
                keys.insert(unescaped)
            }
        }
        return keys
    }

    /// Parse a .strings file and return the set of keys defined in it.
    private func parseStringsKeys(at url: URL) -> Set<String> {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        // .strings format: "key" = "value";
        let pattern = #"^\s*"((?:[^"\\]|\\.)*)"\s*="#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
        var keys = Set<String>()
        let range = NSRange(content.startIndex..., in: content)
        for match in regex.matches(in: content, options: [], range: range) {
            guard match.numberOfRanges >= 2,
                  let keyRange = Range(match.range(at: 1), in: content) else { continue }
            let rawKey = String(content[keyRange])
            let unescaped = rawKey
                .replacingOccurrences(of: "\\\\", with: "\\")
                .replacingOccurrences(of: "\\\"", with: "\"")
            keys.insert(unescaped)
        }
        return keys
    }

    /// Count format specifiers (%d, %@, %f, %1$d, %2$@, %.1f, etc.) in a string.
    private func formatSpecifierCount(in string: String) -> Int {
        let pattern = #"%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh?|ll?|qq?|z|t|L)?[@dDuUxXoOfeEgGcCsSpaAF]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(string.startIndex..., in: string)
        return regex.numberOfMatches(in: string, options: [], range: range)
    }

    /// Parse a .strings file into a key->value dictionary for placeholder validation.
    private func parseStringsKeyValue(at url: URL) -> [String: String] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        let pattern = #"^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return [:]
        }
        var dict: [String: String] = [:]
        let range = NSRange(content.startIndex..., in: content)
        for match in regex.matches(in: content, options: [], range: range) {
            guard match.numberOfRanges >= 3,
                  let keyRange = Range(match.range(at: 1), in: content),
                  let valRange = Range(match.range(at: 2), in: content) else { continue }
            let key = String(content[keyRange])
                .replacingOccurrences(of: "\\\\", with: "\\")
                .replacingOccurrences(of: "\\\"", with: "\"")
            let value = String(content[valRange])
                .replacingOccurrences(of: "\\\\", with: "\\")
                .replacingOccurrences(of: "\\\"", with: "\"")
            dict[key] = value
        }
        return dict
    }

    @Test func allUsedKeysExistInAllLanguages() throws {
        guard let root = projectRoot() else {
            Issue.record("Cannot locate project root (Package.swift not found)")
            return
        }
        let files = swiftSourceFiles(root: root)
        #expect(!files.isEmpty, "No Swift source files found under Sources/")

        let usedKeys = extractUsedKeys(from: files)
        #expect(!usedKeys.isEmpty, "No L() calls found in source code")

        let resourcesDir = root.appending(path: "Sources/ShipNotes/Resources")
        let locales = ["en", "zh-Hans", "ja"]
        var allMissing: [String: [String]] = [:]  // locale -> missing keys

        for locale in locales {
            let stringsURL = resourcesDir
                .appending(path: "\(locale).lproj")
                .appending(path: "Localizable.strings")
            let definedKeys = parseStringsKeys(at: stringsURL)
            #expect(!definedKeys.isEmpty, "No keys parsed from \(locale) Localizable.strings")

            let missing = usedKeys.subtracting(definedKeys).sorted()
            if !missing.isEmpty {
                allMissing[locale] = missing
            }
        }

        #expect(allMissing.isEmpty, "Keys used in code but missing from .strings: \(allMissing.map { "[\($0.key)] \($0.value.prefix(5))" }.joined(separator: "; "))")
    }

    @Test func formatPlaceholderCountsMatchAcrossLanguages() throws {
        guard let root = projectRoot() else {
            Issue.record("Cannot locate project root")
            return
        }
        let resourcesDir = root.appending(path: "Sources/ShipNotes/Resources")
        let locales = ["en", "zh-Hans", "ja"]

        var keyValues: [String: [String: String]] = [:]  // locale -> (key -> value)
        for locale in locales {
            let stringsURL = resourcesDir
                .appending(path: "\(locale).lproj")
                .appending(path: "Localizable.strings")
            keyValues[locale] = parseStringsKeyValue(at: stringsURL)
        }

        guard let enDict = keyValues["en"] else {
            Issue.record("Cannot parse en Localizable.strings")
            return
        }

        var mismatches: [String] = []
        for (key, enValue) in enDict.sorted(by: { $0.key < $1.key }) {
            let enCount = formatSpecifierCount(in: enValue)
            guard enCount > 0 else { continue }

            for locale in ["zh-Hans", "ja"] {
                guard let value = keyValues[locale]?[key] else { continue }
                let localeCount = formatSpecifierCount(in: value)
                if localeCount != enCount {
                    mismatches.append(
                        "[\(locale)] \"\(key)\": en has \(enCount) placeholder(s), \(locale) has \(localeCount)"
                    )
                }
            }
        }

        #expect(mismatches.isEmpty, "Format placeholder mismatches: \(mismatches.prefix(10).joined(separator: "; "))")
    }
}
