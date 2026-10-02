import Foundation

struct ParsedReleaseNotes: Hashable {
    var version: String?
    var locales: [String: String]
    var sourceFiles: [String: URL]
    var sourceDescription: String
    var candidatesByLocale: [String: [ReleaseNoteImportCandidate]] = [:]

    var requiresReview: Bool {
        candidatesByLocale.values.contains { candidates in
            candidates.count > 1 && candidates.first?.confidence != .high
        }
    }

    var defaultCandidateSelections: [String: String] {
        Dictionary(uniqueKeysWithValues: candidatesByLocale.compactMap { locale, candidates in
            guard let candidate = candidates.first else { return nil }
            return (locale, candidate.id)
        })
    }

    func resolvedLocales(using selections: [String: String]) -> [String: String] {
        var resolved = locales
        for (locale, candidates) in candidatesByLocale {
            guard let selectedId = selections[locale],
                  let candidate = candidates.first(where: { $0.id == selectedId }) else { continue }
            resolved[locale] = candidate.text
        }
        return resolved
    }
}

struct ReleaseNoteImportCandidate: Identifiable, Hashable, Sendable {
    enum Confidence: Int, Hashable, Sendable {
        case high = 3
        case medium = 2
        case low = 1

        var displayName: String {
            switch self {
            case .high: L("Recommended")
            case .medium: L("Possible")
            case .low: L("Manual")
            }
        }
    }

    let id: String
    var title: String
    var text: String
    var confidence: Confidence
}

enum ReleaseNotesParserError: Error, LocalizedError {
    case folderUnreadable(URL)
    case unreadableFile(URL)
    case noLocaleFilesFound(URL)
    case yamlMissingLocales(URL)
    case versionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .versionNotFound(let version): L("No release notes matching version %@. Select the correct file.", version)
        case .folderUnreadable(let url): L("Cannot read folder at %@", url.path)
        case .unreadableFile(let url): L("Cannot read file at %@", url.path)
        case .noLocaleFilesFound(let url): L("No locale files found in %@", url.lastPathComponent)
        case .yamlMissingLocales(let url): L("YAML at %@ has no 'locales:' map", url.lastPathComponent)
        }
    }
}

struct ReleaseNotesParser {
    let mapper = LocaleMapper()
    let yaml = MinimalYAML()

    func parse(url: URL, currentVersion: String? = nil, defaultLocale: String? = nil) throws -> ParsedReleaseNotes {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ReleaseNotesParserError.folderUnreadable(url)
        }
        if isDir.boolValue {
            return try parseFolder(url, currentVersion: currentVersion)
        }
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        if ext == "yaml" || ext == "yml" { return try parseYAMLFile(url) }
        if ext == "json" { return try parseJSONFile(url) }
        if name == "changelog.md" || name == "changelog" {
            return try parseChangelog(url, currentVersion: currentVersion, defaultLocale: defaultLocale)
        }
        if ext == "md" || ext == "markdown" || ext == "txt" {
            // Read once and share the text across every format probe. The
            // previous per-probe reads (a) hit the disk up to four times and
            // (b) conflated IO failures with "format doesn't match", silently
            // reporting unreadable files as empty results.
            let text: String
            do {
                text = try FileScannerUtils.readText(at: url)
            } catch {
                throw ReleaseNotesParserError.unreadableFile(url)
            }
            // Try version-history files where each H2 is a version, then a
            // nested "App Store What's New" section contains H4 locale blocks.
            if let versionHistory = tryParseVersionHistoryWhatsNew(text, url: url, currentVersion: currentVersion) {
                return versionHistory
            }
            // Try the multi-locale release-notes-log format first
            // (one file, H2 = version, H3 = language/flag).
            if let multi = tryParseMultiLocaleReleaseNotesLog(text, url: url, currentVersion: currentVersion) {
                return multi
            }
            // Try dash-separated format: one version, `--- Language(Region) ---` blocks.
            if let dashed = tryParseDashSeparatedReleaseNotes(text, url: url, currentVersion: currentVersion) {
                return dashed
            }
            return try parseSingleLocaleFile(url, currentVersion: currentVersion, defaultLocale: defaultLocale, preloadedText: text)
        }
        throw ReleaseNotesParserError.unreadableFile(url)
    }
}
