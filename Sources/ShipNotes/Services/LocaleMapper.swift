import Foundation

struct LocaleMapper {
    static let appStoreLocales: [String] = [
        "ar-SA", "ca", "zh-Hans", "zh-Hant", "hr", "cs", "da", "nl-NL",
        "en-AU", "en-CA", "en-GB", "en-US", "fi", "fr-CA", "fr-FR",
        "de-DE", "el", "he", "hi", "hu", "id", "it", "ja", "ko", "ms",
        "no", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "es-MX", "es-ES",
        "sv", "th", "tr", "uk", "vi"
    ]

    static let aliases: [String: String] = [
        "en": "en-US",
        "zh": "zh-Hans",
        "zh-CN": "zh-Hans",
        "zh-SG": "zh-Hans",
        "zh-TW": "zh-Hant",
        "zh-HK": "zh-Hant",
        "pt": "pt-BR",
        "es": "es-ES",
        "fr": "fr-FR",
        "de": "de-DE",
        "nl": "nl-NL",
        "ar": "ar-SA"
    ]

    /// Deterministic per-language fallback when the exact region isn't in the
    /// App Store list. Without this, `resolve("en-XX")` returned whatever
    /// en-* locale happened to sit first in `appStoreLocales` (en-AU),
    /// silently tagging content with the wrong country.
    static let languageFallbacks: [String: String] = [
        "en": "en-US",
        "fr": "fr-FR",
        "es": "es-ES",
        "pt": "pt-BR",
        "zh": "zh-Hans",
        "de": "de-DE",
        "nl": "nl-NL",
        "ar": "ar-SA",
    ]

    func resolve(_ rawLocale: String) -> String? {
        let normalized = normalize(rawLocale)
        if Self.appStoreLocales.contains(normalized) { return normalized }
        if let mapped = Self.aliases[normalized] { return mapped }
        let lang = normalized.split(separator: "-").first.map(String.init) ?? normalized
        if Self.appStoreLocales.contains(lang) { return lang }
        return Self.languageFallbacks[lang]
    }

    func detectLocale(fromFilename filename: String) -> String? {
        let base = (filename as NSString).deletingPathExtension
        let cleaned = base.replacingOccurrences(of: " ", with: "")
        if cleaned.isEmpty { return nil }
        return cleaned
    }

    /// Tokens that may appear in a path/filename component and map to an App Store locale
    /// (e.g. `en-US`, `zh_Hans`, or adjacent language/region parts).
    static func localeTokens(from value: String) -> [String] {
        let direct = value.replacingOccurrences(of: "_", with: "-")
        var tokens: [String] = []
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        tokens.append(contentsOf: localeTokenRegex.matches(in: value, range: range).compactMap { match in
            let matchRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            guard let range = Range(matchRange, in: value) else { return nil }
            return String(value[range]).replacingOccurrences(of: "_", with: "-")
        })
        tokens.append(direct)

        let separators = CharacterSet(charactersIn: " _-./()[]")
        let parts = value.components(separatedBy: separators).filter { !$0.isEmpty }
        for index in parts.indices.dropLast() {
            let first = parts[index]
            let second = parts[parts.index(after: index)]
            if first.count >= 2, first.count <= 3, second.count >= 2, second.count <= 4,
               first.allSatisfy(\.isLetter), second.allSatisfy(\.isLetter) {
                tokens.append("\(first)-\(second)")
            }
        }
        tokens.append(contentsOf: parts)

        var seen = Set<String>()
        return tokens.filter { token in
            !token.isEmpty && seen.insert(token).inserted
        }
    }

    /// Locale candidates found in a relative screenshot path, strongest first.
    ///
    /// Folders win over the file name, deepest folder first: a folder name is
    /// a deliberate locale choice, while file names mix in words such as
    /// `no-ads`, `try-it-now` or `hi-res` whose first half is also a language
    /// code. Within a component, the whole name counts when it is locale-shaped
    /// (`ja`, `en-US`, `zh_Hans`), and an embedded pair counts only when its
    /// second half is a real region or script (`zh-Hant_6.9inch`, `home_de-DE`).
    /// A bare language code inside a longer name (`01_ja`) is the weakest hint,
    /// and never one of the codes that double as common English words.
    static func pathLocaleHints(_ components: [String]) -> [String] {
        guard !components.isEmpty else { return [] }
        let basenames = components.map { ($0 as NSString).deletingPathExtension }
        let ordered = basenames.dropLast().reversed() + [basenames[basenames.count - 1]]

        var strong: [String] = []
        var weak: [String] = []
        for basename in ordered {
            let whole = basename
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "_", with: "-")
            if isLocaleShaped(whole, allowsBareLanguage: true) {
                // `resolve` understands `lang` and `lang-REGION/Script`, but
                // falls back to the language default for longer tags
                // (`en-GB-home` → en-US, `zh-Hant-TW` → zh-Hans). Hand it the
                // first two subtags only.
                strong.append(whole.split(separator: "-").prefix(2).joined(separator: "-"))
            }

            let range = NSRange(basename.startIndex..<basename.endIndex, in: basename)
            for match in localeTokenRegex.matches(in: basename, range: range) {
                guard let tokenRange = Range(match.range(at: 1), in: basename) else { continue }
                let token = String(basename[tokenRange]).replacingOccurrences(of: "_", with: "-")
                if isLocaleShaped(token, allowsBareLanguage: false) {
                    strong.append(token)
                }
            }

            let parts = basename
                .components(separatedBy: CharacterSet(charactersIn: " _-./()[]"))
                .filter { !$0.isEmpty }
            guard parts.count > 1 else { continue }
            for (first, second) in zip(parts, parts.dropFirst()) {
                let pair = "\(first)-\(second)"
                if isLocaleShaped(pair, allowsBareLanguage: false) {
                    strong.append(pair)
                }
            }
            for part in parts {
                let lowered = part.lowercased()
                guard (2...3).contains(part.count), part.allSatisfy(\.isLetter),
                      !ambiguousBareLanguageCodes.contains(lowered) else { continue }
                weak.append(part)
            }
        }

        var seen = Set<String>()
        return (strong + weak).filter { seen.insert($0.lowercased()).inserted }
    }

    /// Language codes that are also everyday words or abbreviations in file
    /// names ("no ads", "try it", "hi res", "UK store", "Screen VI").
    static let ambiguousBareLanguageCodes: Set<String> = [
        "he", "hi", "id", "it", "ms", "no", "uk", "vi"
    ]

    /// For the ambiguous codes, `xx-YY` pairs such as `no-ad`, `hi-fi` or
    /// `it-is` are English too, so only the language's own region counts.
    static let ambiguousLanguageRegions: [String: String] = [
        "he": "IL", "hi": "IN", "id": "ID", "it": "IT",
        "ms": "MY", "no": "NO", "uk": "UA", "vi": "VN"
    ]

    private static let scriptCodes: Set<String> = ["hans", "hant", "latn", "cyrl", "arab"]

    /// `lang` or `lang-REGION` / `lang-Script` (optionally followed by more
    /// subtags). The second subtag must be an ISO region, a script, or form a
    /// locale/alias App Store Connect knows, so `no-ads` is rejected.
    static func isLocaleShaped(_ token: String, allowsBareLanguage: Bool) -> Bool {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        // Every subtag must be letters, so `zh-Hant_6.9inch_01` as a whole is
        // not mistaken for a locale (its `zh-Hant` part is found separately).
        guard let language = parts.first,
              (2...3).contains(language.count),
              parts.count <= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isLetter } }) else { return false }
        guard parts.count > 1 else { return allowsBareLanguage }

        let second = parts[1]
        let pair = "\(language.lowercased())-\(second)"
        if appStoreLocales.contains(where: { $0.caseInsensitiveCompare(pair) == .orderedSame })
            || aliases.keys.contains(where: { $0.caseInsensitiveCompare(pair) == .orderedSame }) {
            return true
        }
        if let region = ambiguousLanguageRegions[language.lowercased()] {
            return second.caseInsensitiveCompare(region) == .orderedSame
        }
        if second.count == 4 {
            return scriptCodes.contains(second.lowercased())
        }
        if second.count == 2 {
            return Locale.Region(second.uppercased()).isISORegion
        }
        return false
    }

    private static let localeTokenRegex = try! NSRegularExpression(
        pattern: #"(?<![a-zA-Z])([a-zA-Z]{2,3}[-_][a-zA-Z]{2,4})(?![a-zA-Z])"#
    )

    private func normalize(_ locale: String) -> String {
        let parts = locale.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first else { return locale }
        let lang = first.lowercased()
        if parts.count == 1 { return lang }
        let region = parts.dropFirst().joined(separator: "-")
        if region.count == 4 {
            return "\(lang)-\(region.prefix(1).uppercased())\(region.dropFirst().lowercased())"
        }
        return "\(lang)-\(region.uppercased())"
    }
}
