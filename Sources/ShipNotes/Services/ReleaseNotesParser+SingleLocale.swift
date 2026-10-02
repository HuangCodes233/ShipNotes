import Foundation

extension ReleaseNotesParser {
    /// Parse a single per-locale markdown/text file like `de.md` or `en-US.md`.
    /// The locale is inferred from the filename. If the file contains a
    /// structured App Store metadata layout (multiple `## Section` blocks where
    /// one contains a code-fenced multi-version release-notes log), only the
    /// section matching `currentVersion` is extracted. Otherwise the whole file
    /// is used as the release-notes body.
    func parseSingleLocaleFile(
        _ url: URL,
        currentVersion: String?,
        defaultLocale: String? = nil,
        preloadedText: String? = nil
    ) throws -> ParsedReleaseNotes {
        let raw = try preloadedText ?? FileScannerUtils.readText(at: url)
        let resolved: String
        if let detected = mapper.detectLocale(fromFilename: url.lastPathComponent),
           let r = mapper.resolve(detected) {
            resolved = r
        } else if let fallback = defaultLocale {
            // Used when parseFolder picked a file by structural convention
            // (e.g., `ReleaseNotes_v3.0.2.txt`) — the filename has no locale
            // code but we still want to import the content somewhere.
            resolved = fallback
        } else {
            throw ReleaseNotesParserError.noLocaleFilesFound(url)
        }
        let candidates = importCandidates(from: raw, matchingVersion: currentVersion)
        let body = preferredReleaseNotesBody(from: candidates) ?? raw
        let parentName = url.deletingLastPathComponent().lastPathComponent
        return ParsedReleaseNotes(
            version: currentVersion ?? inferVersion(fromFolderName: parentName),
            locales: [resolved: body.trimmingCharacters(in: .whitespacesAndNewlines)],
            sourceFiles: [resolved: url],
            sourceDescription: url.path,
            candidatesByLocale: [resolved: candidates]
        )
    }

    func importCandidates(from text: String, matchingVersion: String?) -> [ReleaseNoteImportCandidate] {
        var candidates: [ReleaseNoteImportCandidate] = []
        let sections = markdownSections(from: text)
        for (index, section) in sections.enumerated() {
            let codeBlocks = extractCodeBlockContents(section.body)
            let rawBody = codeBlocks.first.map {
                extractReleaseNotes(fromCodeBlock: $0, matchingVersion: matchingVersion)
            } ?? stripMarkdownScaffolding(section.body)
            let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            candidates.append(ReleaseNoteImportCandidate(
                id: "section-\(index)",
                title: section.title,
                text: body,
                confidence: candidateConfidence(for: section.title)
            ))
        }

        if let body = legacyVersionedCodeBlockBody(from: text, matchingVersion: matchingVersion) {
            candidates.append(ReleaseNoteImportCandidate(
                id: "version-log",
                title: L("Versioned release notes"),
                text: body,
                confidence: .medium
            ))
        }

        if candidates.isEmpty {
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                candidates.append(ReleaseNoteImportCandidate(
                    id: "whole-file",
                    title: L("Whole file"),
                    text: body,
                    confidence: .low
                ))
            }
        }

        return deduplicated(candidates)
            .sorted {
                if $0.confidence.rawValue != $1.confidence.rawValue {
                    return $0.confidence.rawValue > $1.confidence.rawValue
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func legacyVersionedCodeBlockBody(from text: String, matchingVersion: String?) -> String? {
        let codeBlocks = extractCodeBlockContents(text)
        let versionPattern = #"v?\d+\.\d+(?:\.\d+)?"#
        // Find the first code block that mentions a semver-ish version. That's
        // the "release notes log" in this kind of file — other code blocks
        // (App Name, Subtitle, Description, Keywords) won't contain versions.
        guard let releaseNotesBlock = codeBlocks.first(where: {
            $0.range(of: versionPattern, options: .regularExpression) != nil
        }) else {
            return nil
        }

        return extractReleaseNotes(fromCodeBlock: releaseNotesBlock, matchingVersion: matchingVersion)
    }

    struct MarkdownSection {
        var title: String
        var body: String
    }

    func markdownSections(from text: String) -> [MarkdownSection] {
        var sections: [MarkdownSection] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flush() {
            guard let currentTitle else { return }
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(MarkdownSection(title: currentTitle, body: body))
            currentLines.removeAll()
        }

        for line in text.components(separatedBy: .newlines) {
            if isLevelTwoHeading(line) {
                flush()
                currentTitle = cleanHeadingTitle(line)
            } else if currentTitle != nil {
                currentLines.append(line)
            }
        }
        flush()
        return sections
    }

    func candidateConfidence(for title: String) -> ReleaseNoteImportCandidate.Confidence {
        if isWhatsNewHeading(title) { return .high }
        let normalized = normalizedHeading(title)
        if normalized.contains("release") || normalized.contains("version") || normalized.contains("changelog") {
            return .medium
        }
        return .low
    }

    func deduplicated(_ candidates: [ReleaseNoteImportCandidate]) -> [ReleaseNoteImportCandidate] {
        var seen: Set<String> = []
        var result: [ReleaseNoteImportCandidate] = []
        for candidate in candidates {
            let key = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(candidate)
        }
        return result
    }

    func extractReleaseNotes(fromCodeBlock releaseNotesBlock: String, matchingVersion: String?) -> String {
        // Sub-section separator commonly is `---` on its own line. Split on
        // whole separator lines only — `components(separatedBy: "---")` would
        // also cut inside body text like "a---b".
        let subSections: [String]
        if releaseNotesBlock.range(of: #"(?m)^---\s*$"#, options: .regularExpression) != nil {
            var chunks: [String] = []
            var current: [String] = []
            for line in releaseNotesBlock.components(separatedBy: .newlines) {
                if line.range(of: #"^---\s*$"#, options: .regularExpression) != nil {
                    chunks.append(current.joined(separator: "\n"))
                    current.removeAll()
                } else {
                    current.append(line)
                }
            }
            chunks.append(current.joined(separator: "\n"))
            subSections = chunks
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            subSections = [releaseNotesBlock.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        // Prefer the sub-section that mentions the currently-selected version.
        // `(?![.\d])` keeps `3.0` from matching inside `3.0.1` — `\b` alone
        // is satisfied at the `0`-to-`.` boundary.
        if let version = matchingVersion {
            let escaped = NSRegularExpression.escapedPattern(for: version)
            if let match = subSections.first(where: {
                $0.range(of: #"v?\#(escaped)(?![.\d])"#, options: .regularExpression) != nil
            }) {
                return stripVersionHeader(match)
            }
        }
        // Fallback: latest = first sub-section.
        return subSections.first.map(stripVersionHeader) ?? releaseNotesBlock.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isLevelTwoHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ")
    }

    func isWhatsNewHeading(_ line: String) -> Bool {
        let normalized = normalizedHeading(line)
        return normalized.contains("what'snew")
            || normalized.contains("whatsnew")
            || normalized.contains("releasenotes")
            || normalized.contains("changelog")
            || normalized.contains("版本更新")
            || normalized.contains("更新说明")
            || normalized.contains("更新說明")
    }

    func normalizedHeading(_ line: String) -> String {
        line
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: " ", with: "")
    }

    func cleanHeadingTitle(_ line: String) -> String {
        var title = line.trimmingCharacters(in: .whitespaces)
        while title.hasPrefix("#") {
            title.removeFirst()
        }
        return title.trimmingCharacters(in: .whitespaces)
    }

    func stripMarkdownScaffolding(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return true }
                if trimmed == "---" { return false }
                if trimmed.hasPrefix("**Limit:") || trimmed.hasPrefix("**First release:") { return false }
                return true
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractCodeBlockContents(_ text: String) -> [String] {
        var results: [String] = []
        var inside = false
        var buffer: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inside {
                    results.append(buffer.joined(separator: "\n"))
                    buffer.removeAll()
                    inside = false
                } else {
                    inside = true
                }
            } else if inside {
                buffer.append(line)
            }
        }
        return results
    }

    /// Drop the leading "Was ist neu in vX.Y.Z:" / "What's New in vX.Y.Z:" /
    /// "## vX.Y.Z" / "vX.Y.Z:" header line if present.
    func stripVersionHeader(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces) else { return text }
        let hasVersion = first.range(of: #"v?\d+\.\d+(?:\.\d+)?"#, options: .regularExpression) != nil
        let looksLikeHeader = first.hasSuffix(":") || first.hasPrefix("#") || first.count < 80
        if hasVersion && looksLikeHeader {
            lines.removeFirst()
            // Skip a blank line right after the header for tidier output.
            while let next = lines.first, next.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeFirst()
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
