import Foundation

extension ReleaseNotesParser {
    /// A CHANGELOG serves the version being edited, like every other format.
    /// Taking the top section regardless meant preparing 2.3.0 while 2.4.0 sat
    /// on top imported the wrong notes without any warning.
    func parseChangelog(
        _ url: URL,
        currentVersion: String? = nil,
        defaultLocale: String? = nil
    ) throws -> ParsedReleaseNotes {
        let text = try FileScannerUtils.readText(at: url)
        let sections = parseChangelogSections(text)
        guard !sections.isEmpty else {
            throw ReleaseNotesParserError.noLocaleFilesFound(url)
        }
        let chosen: (version: String, body: String)
        if let currentVersion {
            guard let match = sections.first(where: { logVersionMatches($0.0, requested: currentVersion) }) else {
                throw ReleaseNotesParserError.versionNotFound(currentVersion)
            }
            chosen = match
        } else {
            chosen = sections[0]
        }
        let sourceLocale = defaultLocale.flatMap(mapper.resolve) ?? mapper.resolve("en") ?? "en-US"
        return ParsedReleaseNotes(
            version: chosen.version,
            locales: [sourceLocale: chosen.body],
            sourceFiles: [sourceLocale: url],
            sourceDescription: "\(url.lastPathComponent) · \(chosen.version)"
        )
    }

    /// Version headings such as `## 1.2.0`, `## v1.2`, `# 1.2.0 (2024-05-01)`
    /// or Keep a Changelog's `## [1.2.0] - 2024-05-01`. Only the version
    /// itself is captured, never the date that follows it.
    private static let changelogVersionHeading = try! NSRegularExpression(
        pattern: #"^(#{1,3})\s+\[?v?(\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.]+)?)(?![0-9A-Za-z.])"#
    )
    private static let changelogHeading = try! NSRegularExpression(pattern: #"^(#{1,6})\s"#)
    /// Markdown link definitions (`[2.4.0]: https://…`), which Keep a
    /// Changelog lists at the end of the file — not release-note text.
    private static let linkDefinition = try! NSRegularExpression(pattern: #"^\s{0,3}\[[^\]]+\]:\s*\S+"#)

    func parseChangelogSections(_ text: String) -> [(String, String)] {
        var results: [(String, String)] = []
        var currentVersion: String?
        var versionLevel = 0
        var currentLines: [String] = []

        func closeSection() {
            if let version = currentVersion {
                let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { results.append((version, body)) }
            }
            currentVersion = nil
            currentLines = []
        }

        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = Self.changelogVersionHeading.firstMatch(in: line, range: range),
                let levelRange = Range(match.range(at: 1), in: line),
                let versionRange = Range(match.range(at: 2), in: line)
            {
                closeSection()
                versionLevel = line[levelRange].count
                currentVersion = String(line[versionRange])
                continue
            }
            // A non-version heading at the version's level or above (for
            // example `## [Unreleased]` or `# Links`) ends the section; deeper
            // headings such as `### Added` belong to it.
            if currentVersion != nil,
                let match = Self.changelogHeading.firstMatch(in: line, range: range),
                let levelRange = Range(match.range(at: 1), in: line),
                line[levelRange].count <= versionLevel
            {
                closeSection()
                continue
            }
            if currentVersion != nil, Self.linkDefinition.firstMatch(in: line, range: range) == nil {
                currentLines.append(line)
            }
        }
        closeSection()
        return results
    }
}
