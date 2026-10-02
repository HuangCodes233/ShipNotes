import Foundation

extension ReleaseNotesParser {
    // MARK: - Multi-locale release-notes log
    // A single .md file containing ALL versions × ALL languages, like:
    //   ## v1.7.0 — Title
    //   ### 🇨🇳 简体中文
    //   ```...body...```
    //   ### 🇺🇸 English
    //   ```...body...```
    //   ## v1.6.0 — Title
    //   ...

    func tryParseMultiLocaleReleaseNotesLog(
        _ text: String,
        url: URL,
        currentVersion: String?
    ) -> ParsedReleaseNotes? {
        let versionSections = parseLogVersionSections(text)
        guard !versionSections.isEmpty else { return nil }

        // Only treat this as the log format if at least one H3 maps to a locale.
        // Otherwise it's a regular markdown file and the caller should fall back.
        let canIdentifyAnyLocale = versionSections.contains { vs in
            vs.languageSections.contains { ls in
                identifyLocale(fromHeading: ls.heading) != nil
            }
        }
        guard canIdentifyAnyLocale else { return nil }

        guard let chosen = chooseLogVersionSection(versionSections, currentVersion: currentVersion) else { return nil }

        var locales: [String: String] = [:]
        var sourceFiles: [String: URL] = [:]
        for ls in chosen.languageSections {
            guard let locale = identifyLocale(fromHeading: ls.heading) else { continue }
            let blocks = extractCodeBlockContents(ls.body)
            guard let body = blocks.first else { continue }
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            locales[locale] = trimmed
            sourceFiles[locale] = url
        }
        guard !locales.isEmpty else { return nil }

        return ParsedReleaseNotes(
            version: currentVersion ?? chosen.version,
            locales: locales,
            sourceFiles: sourceFiles,
            sourceDescription: "\(url.lastPathComponent) · v\(chosen.version)",
            candidatesByLocale: [:]  // already confident; no preview required
        )
    }

    struct LogVersionSection {
        var version: String
        var languageSections: [LogLanguageSection]
    }

    struct LogLanguageSection {
        var heading: String
        var body: String
    }

    func parseLogVersionSections(_ text: String) -> [LogVersionSection] {
        var sections: [LogVersionSection] = []
        var currentVersion: String?
        var currentLangHeading: String?
        var currentLangBody: [String] = []
        var currentLangSections: [LogLanguageSection] = []
        var insideCodeFence = false

        func flushLanguage() {
            guard let heading = currentLangHeading else { return }
            currentLangSections.append(LogLanguageSection(
                heading: heading,
                body: currentLangBody.joined(separator: "\n")
            ))
            currentLangHeading = nil
            currentLangBody = []
        }

        func flushVersion() {
            flushLanguage()
            if let version = currentVersion, !currentLangSections.isEmpty {
                sections.append(LogVersionSection(
                    version: version,
                    languageSections: currentLangSections
                ))
            }
            currentVersion = nil
            currentLangSections = []
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code-fence-aware parsing — don't interpret ## or ### inside ```.
            if trimmed.hasPrefix("```") {
                insideCodeFence.toggle()
                if currentLangHeading != nil { currentLangBody.append(line) }
                continue
            }
            if insideCodeFence {
                if currentLangHeading != nil { currentLangBody.append(line) }
                continue
            }

            // H2 (## ...) — version boundary
            if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                flushVersion()
                let headingText = String(trimmed.dropFirst(3))
                if let version = extractVersionFromLogHeading(headingText) {
                    currentVersion = version
                }
                continue
            }

            // H3 (### ...) — language boundary
            if trimmed.hasPrefix("### ") && !trimmed.hasPrefix("#### ") {
                if currentVersion != nil {
                    flushLanguage()
                    currentLangHeading = String(trimmed.dropFirst(4))
                }
                continue
            }

            // Body line (collected only when we're inside a language section)
            if currentLangHeading != nil {
                currentLangBody.append(line)
            }
        }
        flushVersion()
        return sections
    }

    func extractVersionFromLogHeading(_ heading: String) -> String? {
        let pattern = #"v?(\d+\.\d+(?:\.\d+)?)"#
        guard let range = heading.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        var matched = String(heading[range])
        if matched.lowercased().hasPrefix("v") { matched.removeFirst() }
        return matched
    }

    func chooseLogVersionSection(
        _ sections: [LogVersionSection],
        currentVersion: String?
    ) -> LogVersionSection? {
        if let v = currentVersion,
           let match = sections.first(where: { logVersionMatches($0.version, requested: v) }) {
            return match
        }
        return sections.first
    }

    func logVersionMatches(_ sectionVersion: String, requested: String) -> Bool {
        if sectionVersion == requested { return true }
        // "1.7" matches "1.7.0" and vice versa
        if sectionVersion.hasPrefix(requested + ".") { return true }
        if requested.hasPrefix(sectionVersion + ".") { return true }
        return false
    }

    /// Flag emoji → App Store locale. Shared by multi-locale log and dash-separated parsers.
    static let flagEmojiToLocale: [(String, String)] = [
        ("🇨🇳", "zh-Hans"), ("🇸🇬", "zh-Hans"),
        ("🇹🇼", "zh-Hant"), ("🇭🇰", "zh-Hant"), ("🇲🇴", "zh-Hant"),
        ("🇺🇸", "en-US"),
        ("🇬🇧", "en-GB"),
        ("🇦🇺", "en-AU"),
        ("🇨🇦", "en-CA"),
        ("🇯🇵", "ja"),
        ("🇰🇷", "ko"),
        ("🇪🇸", "es-ES"),
        ("🇲🇽", "es-MX"),
        ("🇫🇷", "fr-FR"),
        ("🇩🇪", "de-DE"),
        ("🇮🇹", "it"),
        ("🇧🇷", "pt-BR"),
        ("🇵🇹", "pt-PT"),
        ("🇳🇱", "nl-NL"),
        ("🇷🇺", "ru"),
        ("🇮🇩", "id"),
        ("🇲🇾", "ms"),
        ("🇹🇭", "th"),
        ("🇻🇳", "vi"),
        ("🇹🇷", "tr"),
        ("🇵🇱", "pl"),
        ("🇸🇪", "sv"),
        ("🇳🇴", "no"),
        ("🇩🇰", "da"),
        ("🇫🇮", "fi"),
        ("🇨🇿", "cs"),
        ("🇸🇰", "sk"),
        ("🇭🇺", "hu"),
        ("🇷🇴", "ro"),
        ("🇬🇷", "el"),
        ("🇮🇱", "he"),
        ("🇸🇦", "ar-SA"), ("🇦🇪", "ar-SA"),
        ("🇮🇳", "hi"),
        ("🇺🇦", "uk"),
        ("🇭🇷", "hr")
    ]

    /// Order matters — more specific entries first. Lower-cased for case-insensitive match.
    static let languageNameToLocale: [(String, String)] = [
        ("简体中文", "zh-Hans"),
        ("繁體中文", "zh-Hant"),
        ("繁体中文", "zh-Hant"),
        ("english", "en-US"),
        ("日本語", "ja"),
        ("한국어", "ko"),
        ("español", "es-ES"),
        ("espanol", "es-ES"),
        ("deutsch", "de-DE"),
        ("français", "fr-FR"),
        ("francais", "fr-FR"),
        ("italiano", "it"),
        ("bahasa indonesia", "id"),
        ("indonesia", "id"),
        ("português", "pt-BR"),
        ("portugues", "pt-BR"),
        ("nederlands", "nl-NL"),
        ("русский", "ru"),
        ("ไทย", "th"),
        ("हिन्दी", "hi"),
        ("हिंदी", "hi"),
        ("tiếng việt", "vi"),
        ("türkçe", "tr"),
        ("polski", "pl"),
        ("svenska", "sv"),
        ("norsk", "no"),
        ("dansk", "da"),
        ("suomi", "fi"),
        // Generic English language names as fallback
        ("chinese", "zh-Hans"),
        ("japanese", "ja"),
        ("korean", "ko"),
        ("spanish", "es-ES"),
        ("german", "de-DE"),
        ("french", "fr-FR"),
        ("italian", "it"),
        ("portuguese", "pt-BR"),
        ("dutch", "nl-NL"),
        ("russian", "ru"),
        ("turkish", "tr"),
        ("polish", "pl"),
        ("swedish", "sv"),
        ("norwegian", "no"),
        ("danish", "da"),
        ("finnish", "fi"),
        ("czech", "cs"),
        ("slovak", "sk"),
        ("hungarian", "hu"),
        ("romanian", "ro"),
        ("greek", "el"),
        ("hebrew", "he"),
        ("arabic", "ar-SA"),
        ("hindi", "hi"),
        ("ukrainian", "uk"),
        ("croatian", "hr"),
        ("vietnamese", "vi"),
        ("indonesian", "id"),
        ("malay", "ms"),
        ("thai", "th")
    ]


    /// Map a heading like "### 🇨🇳 简体中文" / "--- English（美国）---" / etc.
    /// to an App Store Connect locale. Tries: flag emoji → explicit locale code
    /// → language name (with optional region override from parens like
    /// "English（英国）" → en-GB, "Español（西班牙）" → es-ES).
    func identifyLocale(fromHeading heading: String) -> String? {
        // 1. Flag emoji takes priority (most specific signal)
        for (flag, locale) in Self.flagEmojiToLocale where heading.contains(flag) {
            return locale
        }
        // 2. Explicit locale code (zh-Hans / en-US / fr-CA)
        let tokens = heading.split { !($0.isLetter || $0 == "-") }
        for token in tokens where token.count >= 4 && token.contains("-") {
            if let resolved = mapper.resolve(String(token)) {
                return resolved
            }
        }
        // 3. Language name + optional region override from parens.
        let regionFromParens = detectRegion(inParens: heading)
        let lower = heading.lowercased()
        for (name, defaultLocale) in Self.languageNameToLocale where lower.contains(name.lowercased()) {
            if let region = regionFromParens,
               let withRegion = combineLanguageWithRegion(name: name.lowercased(), region: region) {
                return withRegion
            }
            return defaultLocale
        }
        // 4. Last resort: any token the locale mapper recognises.
        for token in tokens {
            if let resolved = mapper.resolve(String(token)) {
                return resolved
            }
        }
        return nil
    }

    func detectRegion(inParens heading: String) -> String? {
        // Capture content inside the FIRST `(...)` or full-width `（...）` group.
        let parenPattern = #"[（(]([^）)]+)[）)]"#
        guard let range = heading.range(of: parenPattern, options: .regularExpression) else {
            return nil
        }
        let chunk = String(heading[range])
        for (hint, region) in Self.regionHints where chunk.localizedCaseInsensitiveContains(hint) {
            return region
        }
        return nil
    }

    func combineLanguageWithRegion(name: String, region: String) -> String? {
        // Only languages that have multiple App Store Connect variants.
        let combinations: [String: [String: String]] = [
            "english": ["US": "en-US", "GB": "en-GB", "AU": "en-AU", "CA": "en-CA"],
            "español": ["ES": "es-ES", "MX": "es-MX"],
            "espanol": ["ES": "es-ES", "MX": "es-MX"],
            "spanish": ["ES": "es-ES", "MX": "es-MX"],
            "français": ["FR": "fr-FR", "CA": "fr-CA"],
            "francais": ["FR": "fr-FR", "CA": "fr-CA"],
            "french": ["FR": "fr-FR", "CA": "fr-CA"],
            "português": ["BR": "pt-BR", "PT": "pt-PT"],
            "portugues": ["BR": "pt-BR", "PT": "pt-PT"],
            "portuguese": ["BR": "pt-BR", "PT": "pt-PT"],
            "chinese": ["CN": "zh-Hans", "TW": "zh-Hant", "HK": "zh-Hant", "SG": "zh-Hans"]
        ]
        return combinations[name]?[region]
    }

    /// Region hints written in parens after a language name. Order from most
    /// specific to least to avoid "US" matching "thus" or similar.
    private static let regionHints: [(String, String)] = [
        ("美国", "US"), ("美國", "US"),
        ("英国", "GB"), ("英國", "GB"),
        ("澳大利亚", "AU"), ("澳大利亞", "AU"),
        ("加拿大", "CA"),
        ("西班牙", "ES"),
        ("墨西哥", "MX"),
        ("巴西", "BR"),
        ("葡萄牙", "PT"),
        ("中国", "CN"), ("中國", "CN"), ("中国大陆", "CN"), ("中國大陸", "CN"),
        ("台湾", "TW"), ("台灣", "TW"),
        ("香港", "HK"),
        ("新加坡", "SG"),
        ("法国", "FR"), ("法國", "FR"),
        ("united states", "US"), ("united kingdom", "GB"),
        ("australia", "AU"), ("canada", "CA"),
        ("spain", "ES"), ("mexico", "MX"),
        ("china", "CN"), ("taiwan", "TW"), ("hong kong", "HK"),
        ("brazil", "BR"), ("portugal", "PT"),
        ("france", "FR"), ("germany", "DE"),
        ("usa", "US"), ("u.s.", "US"),
        ("uk", "GB"), ("u.k.", "GB")
    ]
}
