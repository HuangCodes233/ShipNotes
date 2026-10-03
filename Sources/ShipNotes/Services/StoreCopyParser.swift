import Foundation

struct PartialStoreMetadataFields: Hashable, Sendable, Codable {
    var subtitle: String?
    var description: String?
    var keywords: String?
    var promotionalText: String?
    var supportURL: String?
    var marketingURL: String?
    var privacyPolicyURL: String?

    var isEmpty: Bool {
        StoreCopyField.allCases.allSatisfy { field in
            value(for: field)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
    }

    func value(for field: StoreCopyField) -> String? {
        switch field {
        case .subtitle: subtitle
        case .description: description
        case .keywords: keywords
        case .promotionalText: promotionalText
        case .supportURL: supportURL
        case .marketingURL: marketingURL
        case .privacyPolicyURL: privacyPolicyURL
        }
    }

    mutating func setValue(_ value: String, for field: StoreCopyField) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        switch field {
        case .subtitle: subtitle = cleaned
        case .description: description = cleaned
        case .keywords: keywords = cleaned
        case .promotionalText: promotionalText = cleaned
        case .supportURL: supportURL = cleaned
        case .marketingURL: marketingURL = cleaned
        case .privacyPolicyURL: privacyPolicyURL = cleaned
        }
    }

    mutating func merge(_ other: PartialStoreMetadataFields) {
        for field in StoreCopyField.allCases {
            guard let value = other.value(for: field) else { continue }
            setValue(value, for: field)
        }
    }

    func applying(to base: StoreMetadataFields) -> StoreMetadataFields {
        var result = base
        for field in StoreCopyField.allCases {
            guard let value = value(for: field) else { continue }
            result.setValue(value, for: field)
        }
        return result
    }
}

struct ParsedStoreCopy: Hashable, Sendable {
    var locales: [String: PartialStoreMetadataFields]
    var sourceFiles: [String: URL]
    var sourceDescription: String
}

enum StoreCopyParserError: Error, LocalizedError {
    case folderUnreadable(URL)
    case noStoreCopyFound(URL)
    case noLocaleFound(URL)

    var errorDescription: String? {
        switch self {
        case .folderUnreadable(let url):
            L("Cannot read store-copy source at %@", url.path)
        case .noStoreCopyFound(let url):
            L("No store-copy fields found in %@", url.lastPathComponent)
        case .noLocaleFound(let url):
            "Could not infer a locale for \(url.lastPathComponent)"
        }
    }
}

struct StoreCopyParser {
    private let mapper = LocaleMapper()
    private let yaml = MinimalYAML()
    private let supportedExtensions: Set<String> = ["md", "markdown", "txt", "yaml", "yml", "json"]

    func parse(url: URL, defaultLocale: String? = nil) throws -> ParsedStoreCopy {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw StoreCopyParserError.folderUnreadable(url)
        }
        if isDir.boolValue {
            return try parseFolder(url, defaultLocale: defaultLocale)
        }

        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw StoreCopyParserError.noStoreCopyFound(url)
        }
        return try parseFile(url, defaultLocale: defaultLocale)
    }

    private func parseFolder(_ url: URL, defaultLocale: String?) throws -> ParsedStoreCopy {
        let root = preferredMetadataFolder(in: url)
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var locales: [String: PartialStoreMetadataFields] = [:]
        var sourceFiles: [String: URL] = [:]
        for entry in entries.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                // Check if this subfolder is a per-locale folder (e.g. fastlane/metadata/en-US/)
                if let folderLocale = mapper.resolve(entry.lastPathComponent) {
                    if let subEntries = try? FileManager.default.contentsOfDirectory(
                        at: entry, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                    {
                        for subEntry in subEntries {
                            guard supportedExtensions.contains(subEntry.pathExtension.lowercased()) else { continue }
                            if let field = fieldFromFilename(subEntry),
                                let text = try? String(contentsOf: subEntry, encoding: .utf8)
                            {
                                var existing = locales[folderLocale] ?? PartialStoreMetadataFields()
                                existing.setValue(text, for: field)
                                locales[folderLocale] = existing
                                sourceFiles[folderLocale] = entry
                            }
                        }
                    }
                }
                continue
            }
            guard supportedExtensions.contains(entry.pathExtension.lowercased()) else { continue }

            let localeHint = localeFromFilename(entry) ?? defaultLocale
            guard let parsed = try? parseFile(entry, defaultLocale: localeHint, allowPlainDescription: false) else {
                continue
            }
            for (locale, partial) in parsed.locales {
                var existing = locales[locale] ?? PartialStoreMetadataFields()
                existing.merge(partial)
                locales[locale] = existing
                sourceFiles[locale] = parsed.sourceFiles[locale] ?? entry
            }
        }

        guard !locales.isEmpty else {
            throw StoreCopyParserError.noStoreCopyFound(url)
        }
        return ParsedStoreCopy(
            locales: locales,
            sourceFiles: sourceFiles,
            sourceDescription: root == url ? url.lastPathComponent : root.path
        )
    }

    private func preferredMetadataFolder(in url: URL) -> URL {
        FileScannerUtils.preferredMetadataFolder(in: url) ?? url
    }

    private func isDirectory(_ url: URL) -> Bool {
        FileScannerUtils.isDirectory(url)
    }

    private func parseFile(_ url: URL, defaultLocale: String?) throws -> ParsedStoreCopy {
        try parseFile(url, defaultLocale: defaultLocale, allowPlainDescription: true)
    }

    private func parseFile(
        _ url: URL,
        defaultLocale: String?,
        allowPlainDescription: Bool
    ) throws -> ParsedStoreCopy {
        switch url.pathExtension.lowercased() {
        case "json":
            return try parseJSONFile(url, defaultLocale: defaultLocale)
        case "yaml", "yml":
            return try parseYAMLFile(url, defaultLocale: defaultLocale)
        default:
            return try parseMarkdownLikeFile(
                url,
                defaultLocale: defaultLocale,
                allowPlainDescription: allowPlainDescription
            )
        }
    }

    private func parseJSONFile(_ url: URL, defaultLocale: String?) throws -> ParsedStoreCopy {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try parseStructuredObject(object, sourceURL: url, defaultLocale: defaultLocale)
    }

    private func parseYAMLFile(_ url: URL, defaultLocale: String?) throws -> ParsedStoreCopy {
        let text = try FileScannerUtils.readText(at: url)
        let object = try yaml.parse(text)
        return try parseStructuredObject(object, sourceURL: url, defaultLocale: defaultLocale)
    }

    private func parseStructuredObject(
        _ object: Any,
        sourceURL: URL,
        defaultLocale: String?
    ) throws -> ParsedStoreCopy {
        guard let dict = object as? [String: Any] else {
            throw StoreCopyParserError.noStoreCopyFound(sourceURL)
        }

        var locales: [String: PartialStoreMetadataFields] = [:]
        if let localeMap = dict.firstValue(forKeys: ["locales", "localizations", "metadata"]) as? [String: Any] {
            mergeLocaleMap(localeMap, into: &locales)
        } else {
            mergeLocaleMap(dict, into: &locales)
        }

        if locales.isEmpty, let partial = partialFields(from: dict), !partial.isEmpty {
            guard let locale = resolvedDefaultLocale(defaultLocale, sourceURL: sourceURL) else {
                throw StoreCopyParserError.noLocaleFound(sourceURL)
            }
            locales[locale] = partial
        }

        guard !locales.isEmpty else {
            throw StoreCopyParserError.noStoreCopyFound(sourceURL)
        }
        return ParsedStoreCopy(
            locales: locales,
            sourceFiles: Dictionary(uniqueKeysWithValues: locales.keys.map { ($0, sourceURL) }),
            sourceDescription: sourceURL.lastPathComponent
        )
    }

    private func mergeLocaleMap(_ dict: [String: Any], into locales: inout [String: PartialStoreMetadataFields]) {
        for (rawLocale, value) in dict {
            guard let locale = mapper.resolve(rawLocale) else { continue }
            let partial: PartialStoreMetadataFields?
            if let fields = value as? [String: Any] {
                partial = partialFields(from: fields)
            } else if let stringValue = coerceString(value) {
                var fallback = PartialStoreMetadataFields()
                fallback.setValue(stringValue, for: .description)
                partial = fallback
            } else {
                partial = nil
            }
            guard let partial, !partial.isEmpty else { continue }
            var existing = locales[locale] ?? PartialStoreMetadataFields()
            existing.merge(partial)
            locales[locale] = existing
        }
    }

    private func partialFields(from dict: [String: Any]) -> PartialStoreMetadataFields? {
        var partial = PartialStoreMetadataFields()
        for (key, value) in dict {
            guard let field = field(from: key), let text = coerceString(value) else { continue }
            partial.setValue(text, for: field)
        }
        return partial.isEmpty ? nil : partial
    }

    private func parseMarkdownLikeFile(
        _ url: URL,
        defaultLocale: String?,
        allowPlainDescription: Bool
    ) throws -> ParsedStoreCopy {
        let text = try FileScannerUtils.readText(at: url)

        if let field = fieldFromFilename(url) {
            let localeBlocks = parseLocaleBlocks(text)
            if !localeBlocks.isEmpty {
                let locales = Dictionary(
                    uniqueKeysWithValues: localeBlocks.map { locale, body in
                        var partial = PartialStoreMetadataFields()
                        partial.setValue(body, for: field)
                        return (locale, partial)
                    })
                return ParsedStoreCopy(
                    locales: locales,
                    sourceFiles: Dictionary(uniqueKeysWithValues: locales.keys.map { ($0, url) }),
                    sourceDescription: url.lastPathComponent
                )
            }
        }

        var partial = parseMarkdownSections(text)
        if partial.isEmpty {
            partial = parseLabelBlocks(text)
        }
        if partial.isEmpty, let field = fieldFromFilename(url) {
            partial.setValue(text, for: field)
        }
        if partial.isEmpty, allowPlainDescription {
            partial.setValue(text, for: .description)
        }

        guard !partial.isEmpty else {
            throw StoreCopyParserError.noStoreCopyFound(url)
        }
        guard let locale = resolvedDefaultLocale(defaultLocale, sourceURL: url) else {
            throw StoreCopyParserError.noLocaleFound(url)
        }
        return ParsedStoreCopy(
            locales: [locale: partial],
            sourceFiles: [locale: url],
            sourceDescription: url.lastPathComponent
        )
    }

    private func parseMarkdownSections(_ text: String) -> PartialStoreMetadataFields {
        var partial = PartialStoreMetadataFields()
        let sections = markdownSections(text)
        for section in sections {
            guard let field = field(from: section.heading) else { continue }
            partial.setValue(extractSectionValue(section.body), for: field)
        }
        return partial
    }

    private func parseLocaleBlocks(_ text: String) -> [(locale: String, body: String)] {
        var blocks: [(locale: String, body: String)] = []
        var currentLocale: String?
        var currentBody: [String] = []
        var insideFence = false

        func flush() {
            guard let locale = currentLocale else { return }
            let value = cleanLocaleBlockBody(currentBody.joined(separator: "\n"))
            if !value.isEmpty {
                blocks.append((locale, value))
            }
            currentBody = []
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideFence.toggle()
                if currentLocale != nil { currentBody.append(line) }
                continue
            }

            if !insideFence, let locale = localeFromSectionHeading(trimmed) {
                flush()
                currentLocale = locale
                continue
            }

            if currentLocale != nil {
                currentBody.append(line)
            }
        }
        flush()
        return blocks
    }

    private func cleanLocaleBlockBody(_ text: String) -> String {
        var value = extractSectionValue(text)
        value = value.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return true }
            if trimmed.hasPrefix("#") { return false }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("chars]") { return false }
            return true
        }.joined(separator: "\n")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func markdownSections(_ text: String) -> [(heading: String, body: String)] {
        var sections: [(heading: String, body: String)] = []
        var currentHeading: String?
        var currentBody: [String] = []
        var insideFence = false

        func flush() {
            guard let currentHeading else { return }
            sections.append((currentHeading, currentBody.joined(separator: "\n")))
            currentBody = []
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideFence.toggle()
                if currentHeading != nil { currentBody.append(line) }
                continue
            }

            if !insideFence,
                trimmed.hasPrefix("#"),
                let firstTextIndex = trimmed.firstIndex(where: { $0 != "#" && !$0.isWhitespace })
            {
                flush()
                currentHeading = String(trimmed[firstTextIndex...]).trimmingCharacters(in: .whitespaces)
                continue
            }

            if currentHeading != nil {
                currentBody.append(line)
            }
        }
        flush()
        return sections
    }

    private func parseLabelBlocks(_ text: String) -> PartialStoreMetadataFields {
        var partial = PartialStoreMetadataFields()
        var currentField: StoreCopyField?
        var currentBody: [String] = []

        func flush() {
            guard let currentField else { return }
            partial.setValue(currentBody.joined(separator: "\n"), for: currentField)
            currentBody = []
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let (field, remainder) = labelLine(trimmed) {
                flush()
                currentField = field
                if !remainder.isEmpty { currentBody.append(remainder) }
            } else if currentField != nil {
                currentBody.append(line)
            }
        }
        flush()
        return partial
    }

    private func labelLine(_ line: String) -> (StoreCopyField, String)? {
        guard let separator = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }
        let label = String(line[..<separator])
        guard let field = field(from: label) else { return nil }
        let remainder = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        return (field, remainder)
    }

    private func extractSectionValue(_ body: String) -> String {
        if let fenced = firstFencedCodeBlock(in: body), !fenced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return fenced
        }
        let cleaned = body.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { return false }
            if trimmed.hasPrefix("**Limit") || trimmed.hasPrefix("**限制") { return false }
            if trimmed.hasPrefix("Limit:") || trimmed.hasPrefix("限制:") { return false }
            return true
        }
        return cleaned.joined(separator: "\n")
    }

    private func firstFencedCodeBlock(in text: String) -> String? {
        var insideFence = false
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if insideFence {
                    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                insideFence = true
                lines = []
                continue
            }
            if insideFence {
                lines.append(line)
            }
        }
        return nil
    }

    private func resolvedDefaultLocale(_ defaultLocale: String?, sourceURL: URL) -> String? {
        if let defaultLocale, let resolved = mapper.resolve(defaultLocale) {
            return resolved
        }
        return localeFromFilename(sourceURL)
    }

    private func localeFromFilename(_ url: URL) -> String? {
        let base = (url.lastPathComponent as NSString).deletingPathExtension
        let normalized =
            base
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let tokens = normalized.split(separator: "-").map(String.init)

        for length in stride(from: min(3, tokens.count), through: 1, by: -1) {
            for start in 0...(tokens.count - length) {
                let candidate = tokens[start..<(start + length)].joined(separator: "-")
                if let locale = mapper.resolve(candidate) {
                    return locale
                }
            }
        }
        return mapper.resolve(base)
    }

    private func localeFromSectionHeading(_ heading: String) -> String? {
        let cleaned =
            heading
            .replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .trimmingCharacters(in: .whitespaces)

        let parentheticalPattern = #"\(([A-Za-z]{2,3}(?:[-_][A-Za-z]{2,4})?)\)"#
        if let range = cleaned.range(of: parentheticalPattern, options: .regularExpression) {
            let raw = cleaned[range]
                .dropFirst()
                .dropLast()
                .replacingOccurrences(of: "_", with: "-")
            if let locale = mapper.resolve(String(raw)) {
                return locale
            }
        }

        let languageNames: [(String, String)] = [
            ("english", "en-US"),
            ("日本語", "ja"),
            ("japanese", "ja"),
            ("简体中文", "zh-Hans"),
            ("簡體中文", "zh-Hans"),
            ("simplified chinese", "zh-Hans"),
            ("繁體中文", "zh-Hant"),
            ("繁体中文", "zh-Hant"),
            ("traditional chinese", "zh-Hant"),
            ("한국어", "ko"),
            ("korean", "ko"),
            ("tiếng việt", "vi"),
            ("vietnamese", "vi"),
            ("français", "fr-FR"),
            ("french", "fr-FR"),
            ("español", "es-ES"),
            ("spanish", "es-ES"),
        ]
        let lowercased = cleaned.lowercased()
        for (name, locale) in languageNames where lowercased.contains(name) {
            return locale
        }

        for token in cleaned.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }) {
            let candidate = String(token).replacingOccurrences(of: "_", with: "-")
            if let locale = mapper.resolve(candidate) {
                return locale
            }
        }
        return nil
    }

    private func fieldFromFilename(_ url: URL) -> StoreCopyField? {
        field(from: (url.lastPathComponent as NSString).deletingPathExtension)
    }

    private func field(from raw: String) -> StoreCopyField? {
        let key = raw.lowercased()
        let compact = key.filter { $0.isLetter || $0.isNumber }

        if compact.contains("whatsnew") || key.contains("what's new") || key.contains("版本更新") {
            return nil
        }
        if compact.contains("appname") || key.contains("应用名称") || key.contains("app 名称") {
            return nil
        }
        if compact.contains("subtitle") || compact == "sub" || key.contains("副标题") || key.contains("副標題")
            || key.contains("サブタイトル")
        {
            return .subtitle
        }
        if compact.contains("privacyurl") || compact.contains("privacypolicy") || compact.contains("privacy")
            || key.contains("隐私政策") || key.contains("隱私政策") || key.contains("プライバシー")
        {
            return .privacyPolicyURL
        }
        if compact.contains("supporturl") || compact.contains("supportlink") || key.contains("支持 url")
            || key.contains("サポート url")
        {
            return .supportURL
        }
        if compact.contains("marketingurl") || compact.contains("marketinglink") || key.contains("营销 url")
            || key.contains("マーケティング url")
        {
            return .marketingURL
        }
        if compact.contains("promotionaltext") || compact.contains("promotext") || compact == "promo"
            || key.contains("推广文本") || key.contains("宣傳文字") || key.contains("プロモーション")
        {
            return .promotionalText
        }
        if compact.contains("keyword") || key.contains("关键词") || key.contains("關鍵字") || key.contains("キーワード") {
            return .keywords
        }
        if compact.contains("description") || compact == "desc" || key.contains("描述") || key.contains("说明")
            || key.contains("説明") || key.contains("beschreibung")
        {
            return .description
        }
        return nil
    }

    private func coerceString(_ value: Any) -> String? {
        switch value {
        case let string as String:
            string
        case let number as NSNumber:
            number.stringValue
        default:
            nil
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func firstValue(forKeys keys: [String]) -> Any? {
        for key in keys {
            if let value = self[key] { return value }
            if let match = first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
                return match.value
            }
        }
        return nil
    }
}
