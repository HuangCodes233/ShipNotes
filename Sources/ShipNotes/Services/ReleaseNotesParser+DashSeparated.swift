import Foundation

extension ReleaseNotesParser {
    // MARK: - Dash-separated release notes
    // One version per file, sections like:
    //   ========== v3.0.0 Release Notes ==========
    //   --- 日本語（主要）---
    //   body...
    //   --- Français ---
    //   body...
    //   --- English（美国）---
    //   body...
    //   --- English（英国）---
    //   body...

    func tryParseDashSeparatedReleaseNotes(
        _ text: String,
        url: URL,
        currentVersion: String?
    ) -> ParsedReleaseNotes? {
        let sections = parseDashSeparatedSections(text)
        guard sections.count >= 2 else { return nil }

        var locales: [String: String] = [:]
        var sourceFiles: [String: URL] = [:]
        for section in sections {
            guard let locale = identifyLocale(fromHeading: section.heading) else { continue }
            let body = section.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            // First-write-wins: if two sections map to the same locale, keep the first one.
            if locales[locale] == nil {
                locales[locale] = body
                sourceFiles[locale] = url
            }
        }
        // Only treat this as the right format if we matched at least 2 locales.
        guard locales.count >= 2 else { return nil }

        let inferredVersion = inferVersionFromText(text)
        return ParsedReleaseNotes(
            version: currentVersion ?? inferredVersion
                ?? inferVersion(fromFolderName: url.deletingPathExtension().lastPathComponent),
            locales: locales,
            sourceFiles: sourceFiles,
            sourceDescription: url.lastPathComponent + (inferredVersion.map { " · v\($0)" } ?? ""),
            candidatesByLocale: [:]
        )
    }

    struct DashSection {
        var heading: String
        var body: String
    }

    /// Section separator: 2+ dashes, content, 2+ dashes. Tolerates spaces.
    /// Precompiled — this runs against every line of every candidate file.
    private static let dashSeparator = try! NSRegularExpression(
        pattern: #"^-{2,}\s*(.+?)\s*-{2,}\s*$"#)

    func parseDashSeparatedSections(_ text: String) -> [DashSection] {
        var sections: [DashSection] = []
        var currentHeading: String?
        var currentBody: [String] = []
        var insideCodeFence = false

        func flush() {
            guard let heading = currentHeading else { return }
            sections.append(
                DashSection(
                    heading: heading,
                    body: currentBody.joined(separator: "\n")
                ))
            currentHeading = nil
            currentBody = []
        }

        for line in text.components(separatedBy: .newlines) {
            // Code-fence-aware: a `--- 日本語 ---` line inside ``` is content,
            // not a section boundary.
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                insideCodeFence.toggle()
                if currentHeading != nil { currentBody.append(line) }
                continue
            }
            if insideCodeFence {
                if currentHeading != nil { currentBody.append(line) }
                continue
            }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if Self.dashSeparator.firstMatch(in: line, range: range) != nil {
                let raw = line.trimmingCharacters(in: .whitespaces)
                let trimmed =
                    raw
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                    .trimmingCharacters(in: .whitespaces)
                flush()
                currentHeading = trimmed
                continue
            }
            if currentHeading != nil {
                currentBody.append(line)
            }
        }
        flush()
        return sections
    }

    func inferVersionFromText(_ text: String) -> String? {
        ReleaseNotesParser.firstVersionMatch(in: text)
    }
}
