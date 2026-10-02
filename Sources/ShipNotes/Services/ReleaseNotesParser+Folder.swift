import Foundation

extension ReleaseNotesParser {
    func parseFolder(_ folder: URL, currentVersion: String? = nil) throws -> ParsedReleaseNotes {
        let fm = FileManager.default
        // Sort so same-locale file conflicts resolve deterministically
        // (contentsOfDirectory order is unspecified on APFS).
        let contents = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .sorted { $0.path < $1.path }
        let mdFiles = contents.filter {
            let e = $0.pathExtension.lowercased()
            return e == "md" || e == "markdown" || e == "txt"
        }

        var locales: [String: String] = [:]
        var sourceFiles: [String: URL] = [:]
        var candidatesByLocale: [String: [ReleaseNoteImportCandidate]] = [:]
        for file in mdFiles {
            guard let raw = mapper.detectLocale(fromFilename: file.lastPathComponent),
                  let resolved = mapper.resolve(raw) else { continue }
            let text = try FileScannerUtils.readText(at: file)
            let candidates = importCandidates(from: text, matchingVersion: currentVersion)
            let body = preferredReleaseNotesBody(from: candidates) ?? text
            locales[resolved] = body.trimmingCharacters(in: .whitespacesAndNewlines)
            sourceFiles[resolved] = file
            candidatesByLocale[resolved] = candidates
        }

        if locales.isEmpty {
            for entry in contents {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
                guard let resolvedLocale = mapper.resolve(entry.lastPathComponent) else { continue }
                if let subFiles = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil) {
                    let noteFiles = subFiles
                        .sorted { $0.path < $1.path }
                        .filter { file in
                            let name = ((file.lastPathComponent as NSString).deletingPathExtension).lowercased().filter { $0.isLetter }
                            return ["releasenotes", "whatsnew", "release", "notes"].contains(name)
                        }
                    if let noteFile = noteFiles.first, let text = try? FileScannerUtils.readText(at: noteFile) {
                        let candidates = importCandidates(from: text, matchingVersion: currentVersion)
                        let body = preferredReleaseNotesBody(from: candidates) ?? text
                        locales[resolvedLocale] = body.trimmingCharacters(in: .whitespacesAndNewlines)
                        sourceFiles[resolvedLocale] = noteFile
                        candidatesByLocale[resolvedLocale] = candidates
                    }
                }
            }
        }

        if locales.isEmpty {
            // Convention-based release-notes file like `ReleaseNotes_v3.0.2.txt`
            // / `release_notes_1.8.md` / `release-notes.md`. Pick the one that
            // matches `currentVersion` (or highest if no match) and recurse
            // through the single-file path, which already knows how to handle
            // multi-locale-log + dash-separated + plain formats.
            if let stampedFile = try pickVersionStampedReleaseNotesFile(from: mdFiles, currentVersion: currentVersion) {
                // If the stamped file has no locale-coded name and is plain
                // text (no dash-separated / multi-locale-log structure), the
                // single-file path will still need a default locale.
                return try parse(url: stampedFile, currentVersion: currentVersion, defaultLocale: "en-US")
            }
            if let yamlFile = contents.first(where: { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }) {
                return try parseYAMLFile(yamlFile)
            }
            if let nestedFolder = nestedReleaseNotesFolder(in: contents) {
                return try parseFolder(nestedFolder, currentVersion: currentVersion)
            }
            if let nestedSource = try recursiveReleaseNotesSource(in: folder, currentVersion: currentVersion) {
                let defaultLocale = isDirectory(nestedSource) ? nil : "en-US"
                return try parse(url: nestedSource, currentVersion: currentVersion, defaultLocale: defaultLocale)
            }
            throw ReleaseNotesParserError.noLocaleFilesFound(folder)
        }

        let version = currentVersion ?? inferVersion(fromFolderName: folder.lastPathComponent)
        return ParsedReleaseNotes(
            version: version,
            locales: locales,
            sourceFiles: sourceFiles,
            sourceDescription: folder.path,
            candidatesByLocale: candidatesByLocale
        )
    }

    func preferredReleaseNotesBody(from candidates: [ReleaseNoteImportCandidate]) -> String? {
        if let recommended = candidates.first(where: { $0.confidence == .high }) {
            return recommended.text
        }
        return candidates.first?.text
    }

    /// Find `ReleaseNotes_v3.0.2.txt` / `release_notes_1.8.md` /
    /// `release-notes.md` style files inside a dropped folder. Prefer one that
    /// matches `currentVersion` (exact or prefix); otherwise return the file
    /// with the highest version number embedded in its name; otherwise return
    /// the first un-versioned `release-notes` file (if any).
    func pickVersionStampedReleaseNotesFile(from files: [URL], currentVersion: String?) throws -> URL? {
        // Match `release notes`, `release_notes`, `release-notes`, `releasenotes`
        // anywhere in the basename, case-insensitive. Optionally followed by
        // an embedded version like `v3.0.2` / `3.0.2`.
        let namePattern = #"(?i)release[ _\-]?notes"#
        let versionPattern = #"(\d+\.\d+(?:\.\d+)?)"#

        struct Candidate { let url: URL; let version: String? }
        var candidates: [Candidate] = []
        for file in files {
            let basename = (file.lastPathComponent as NSString).deletingPathExtension
            guard basename.range(of: namePattern, options: .regularExpression) != nil else { continue }
            let v = basename.range(of: versionPattern, options: .regularExpression).map { String(basename[$0]) }
            candidates.append(Candidate(url: file, version: v))
        }
        guard !candidates.isEmpty else { return nil }

        // 1. Exact version match, or one side is a numeric prefix of the other
        //    (`release_notes_1.8.md` should serve version `1.8.0`).
        if let v = currentVersion {
            if let exact = candidates.first(where: { candidate in
                guard let cv = candidate.version else { return false }
                return logVersionMatches(cv, requested: v)
            }) {
                return exact.url
            }
            if let unversioned = candidates.first(where: { $0.version == nil }) { return unversioned.url }
            throw ReleaseNotesParserError.versionNotFound(v)
        }

        // 2. Highest-numbered versioned file (semver-style numeric compare).
        let versionedSorted = candidates
            .filter { $0.version != nil }
            .sorted { $0.version!.compare($1.version!, options: .numeric) == .orderedDescending }
        if let highest = versionedSorted.first { return highest.url }

        // 3. Any unversioned `release-notes` file.
        return candidates.first { $0.version == nil }?.url
    }

    func nestedReleaseNotesFolder(in contents: [URL]) -> URL? {
        let preferredFolderNames: Set<String> = [
            "appstore",
            "metadata",
            "appstoremetadata",
            "appstoreconnectmetadata",
            "releasenotes",
            "release",
            "whatsnew",
            "locales"
        ]

        return contents.first { url in
            guard isDirectory(url) else { return false }
            return preferredFolderNames.contains(normalizedFolderName(url.lastPathComponent))
        }
    }

    func recursiveReleaseNotesSource(in folder: URL, currentVersion: String?) throws -> URL? {
        let maxDepth = 4
        var folderCandidates: [URL] = []
        var fileCandidates: [URL] = []

        func walk(_ current: URL, depth: Int) {
            guard depth <= maxDepth else { return }
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: nil
            )) ?? []
            for child in contents.sorted(by: { $0.path < $1.path }) {
                let childIsDirectory = isDirectory(child)
                if FileScannerUtils.shouldSkip(child, isDirectory: childIsDirectory) { continue }
                if childIsDirectory {
                    if nestedFolderScore(child) > 0 {
                        folderCandidates.append(child)
                    }
                    walk(child, depth: depth + 1)
                } else if isLikelyReleaseNotesFile(child) {
                    fileCandidates.append(child)
                }
            }
        }

        walk(folder, depth: 0)

        if let folder = folderCandidates.sorted(by: { lhs, rhs in
            let lhsScore = nestedFolderScore(lhs)
            let rhsScore = nestedFolderScore(rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.path.count < rhs.path.count
        }).first {
            return folder
        }

        if let stamped = try pickVersionStampedReleaseNotesFile(from: fileCandidates, currentVersion: currentVersion) {
            return stamped
        }

        return fileCandidates.sorted(by: { lhs, rhs in
            let lhsScore = releaseNotesFileScore(lhs)
            let rhsScore = releaseNotesFileScore(rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.path.count < rhs.path.count
        }).first
    }

    func nestedFolderScore(_ url: URL) -> Int {
        let normalized = normalizedFolderName(url.lastPathComponent)
        let path = url.path.lowercased()
        var score: Int
        switch normalized {
        case "fastlanemetadata", "fastlane", "metadata": score = 120
        case "appstoremetadata", "appstoreconnectmetadata": score = 115
        case "appstore": score = 100
        case "releasenotes": score = 90
        case "whatsnew": score = 85
        case "release", "locales": score = 70
        default: score = 0
        }
        if path.contains("/fastlane/") { score += 15 }
        if path.contains("/appstore/") { score += 10 }
        return score
    }

    func isLikelyReleaseNotesFile(_ url: URL) -> Bool {
        ["md", "markdown", "txt", "yaml", "yml", "json"].contains(url.pathExtension.lowercased())
            && releaseNotesFileScore(url) > 0
    }

    func releaseNotesFileScore(_ url: URL) -> Int {
        let lowerPath = url.path.lowercased()
        let basename = ((url.lastPathComponent as NSString).deletingPathExtension).lowercased()
        let normalized = normalizedFolderName(basename)
        var score = 0
        if normalized == "changelog" { score += 100 }
        if normalized.contains("releasenotes") { score += 100 }
        if normalized.contains("whatsnew") { score += 90 }
        if normalized.contains("versionhistory") { score += 70 }
        if normalized.contains("appstoremetadata") { score += 65 }
        if lowerPath.contains("/appstore/") { score += 20 }
        if lowerPath.contains("/metadata/") { score += 15 }
        return score
    }

    func normalizedFolderName(_ name: String) -> String {
        name
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    func inferVersion(fromFolderName name: String) -> String? {
        let pattern = #"^\d+(\.\d+){1,2}([-+][\w.]+)?$"#
        if name.range(of: pattern, options: .regularExpression) != nil { return name }
        return nil
    }
}
