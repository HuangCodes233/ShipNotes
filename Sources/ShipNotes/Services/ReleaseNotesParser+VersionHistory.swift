import Foundation

extension ReleaseNotesParser {
    // MARK: - Version-history release notes
    // A project changelog can track one version per H2, with internal QA notes
    // around a nested "App Store What's New" section:
    //   ## 1.0.2 (Build 12)
    //   ### Status
    //   ...
    //   ### App Store What's New
    //   #### English (en)
    //   User-facing notes only.
    //   #### Japanese (ja)
    //   ...
    //   ### Validation
    //   ...

    func tryParseVersionHistoryWhatsNew(
        _ text: String,
        url: URL,
        currentVersion: String?
    ) -> ParsedReleaseNotes? {
        let versionBlocks = parseVersionHistoryBlocks(text)
        guard !versionBlocks.isEmpty else { return nil }
        guard let chosen = chooseVersionHistoryBlock(versionBlocks, currentVersion: currentVersion) else { return nil }
        guard let whatsNew = extractWhatsNewHeadingSection(from: chosen.body) else { return nil }

        var locales: [String: String] = [:]
        var sourceFiles: [String: URL] = [:]
        for section in parseLocaleHeadingSections(whatsNew) {
            let body = normalizedReleaseNotesBody(from: section.body, matchingVersion: currentVersion)
            guard !body.isEmpty else { continue }
            if locales[section.locale] == nil {
                locales[section.locale] = body
                sourceFiles[section.locale] = url
            }
        }
        guard !locales.isEmpty else { return nil }

        return ParsedReleaseNotes(
            version: currentVersion ?? chosen.version,
            locales: locales,
            sourceFiles: sourceFiles,
            sourceDescription: "\(url.lastPathComponent) · v\(chosen.version)",
            candidatesByLocale: [:]
        )
    }

    struct VersionHistoryBlock {
        var version: String
        var title: String
        var body: String
    }

    struct LocaleHeadingSection {
        var locale: String
        var body: String
    }

    func parseVersionHistoryBlocks(_ text: String) -> [VersionHistoryBlock] {
        var blocks: [VersionHistoryBlock] = []
        var currentTitle: String?
        var currentVersion: String?
        var currentLines: [String] = []
        var insideCodeFence = false

        func flush() {
            guard let title = currentTitle, let version = currentVersion else {
                currentTitle = nil
                currentVersion = nil
                currentLines = []
                return
            }
            blocks.append(VersionHistoryBlock(
                version: version,
                title: title,
                body: currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            currentTitle = nil
            currentVersion = nil
            currentLines = []
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                insideCodeFence.toggle()
                if currentTitle != nil { currentLines.append(line) }
                continue
            }

            if !insideCodeFence,
               let heading = markdownHeading(line),
               heading.level == 2 {
                flush()
                currentTitle = heading.title
                currentVersion = extractVersionFromLogHeading(heading.title)
                continue
            }

            if currentTitle != nil {
                currentLines.append(line)
            }
        }
        flush()
        return blocks
    }

    func chooseVersionHistoryBlock(
        _ blocks: [VersionHistoryBlock],
        currentVersion: String?
    ) -> VersionHistoryBlock? {
        if let version = currentVersion,
           let match = blocks.first(where: { logVersionMatches($0.version, requested: version) }) {
            return match
        }
        return blocks.first
    }

    func extractWhatsNewHeadingSection(from text: String) -> String? {
        var isCollecting = false
        var collectingLevel: Int?
        var lines: [String] = []
        var insideCodeFence = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                insideCodeFence.toggle()
                if isCollecting { lines.append(line) }
                continue
            }

            if !insideCodeFence, let heading = markdownHeading(line) {
                if isCollecting {
                    if let level = collectingLevel, heading.level <= level {
                        break
                    }
                } else if isWhatsNewHeading(heading.title) {
                    isCollecting = true
                    collectingLevel = heading.level
                    continue
                }
            }

            if isCollecting {
                lines.append(line)
            }
        }

        let section = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return section.isEmpty ? nil : section
    }

    func parseLocaleHeadingSections(_ text: String) -> [LocaleHeadingSection] {
        var sections: [LocaleHeadingSection] = []
        var currentLocale: String?
        var currentLevel: Int?
        var currentLines: [String] = []
        var insideCodeFence = false

        func flush() {
            guard let locale = currentLocale else { return }
            sections.append(LocaleHeadingSection(
                locale: locale,
                body: currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            currentLocale = nil
            currentLevel = nil
            currentLines = []
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                insideCodeFence.toggle()
                if currentLocale != nil { currentLines.append(line) }
                continue
            }

            if !insideCodeFence, let heading = markdownHeading(line) {
                if let locale = identifyLocale(fromHeading: heading.title) {
                    flush()
                    currentLocale = locale
                    currentLevel = heading.level
                    continue
                }

                if let level = currentLevel, heading.level <= level {
                    flush()
                    continue
                }
            }

            if currentLocale != nil {
                currentLines.append(line)
            }
        }
        flush()
        return sections
    }

    func normalizedReleaseNotesBody(from text: String, matchingVersion: String?) -> String {
        let codeBlocks = extractCodeBlockContents(text)
        let raw = codeBlocks.first.map {
            extractReleaseNotes(fromCodeBlock: $0, matchingVersion: matchingVersion)
        } ?? stripMarkdownScaffolding(text)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func markdownHeading(_ line: String) -> (level: Int, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let afterHashes = trimmed.dropFirst(hashes.count)
        guard afterHashes.first == " " else { return nil }
        let title = afterHashes.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (hashes.count, title)
    }
}
