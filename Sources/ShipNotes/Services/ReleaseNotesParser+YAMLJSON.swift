import Foundation

extension ReleaseNotesParser {
    func parseYAMLFile(_ url: URL) throws -> ParsedReleaseNotes {
        let text = try FileScannerUtils.readText(at: url)
        let tree = try yaml.parse(text)
        let version = (tree["version"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }

        guard let rawLocales = tree["locales"] as? [String: Any] else {
            throw ReleaseNotesParserError.yamlMissingLocales(url)
        }
        var locales: [String: String] = [:]
        var sourceFiles: [String: URL] = [:]
        for (key, value) in rawLocales {
            guard let resolved = mapper.resolve(key) else { continue }
            if let text = value as? String {
                locales[resolved] = text
                sourceFiles[resolved] = url
            }
        }
        return ParsedReleaseNotes(
            version: version,
            locales: locales,
            sourceFiles: sourceFiles,
            sourceDescription: url.path
        )
    }

    func parseJSONFile(_ url: URL) throws -> ParsedReleaseNotes {
        let data = try Data(contentsOf: url)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReleaseNotesParserError.yamlMissingLocales(url)
        }
        let version = obj["version"] as? String
        guard let rawLocales = obj["locales"] as? [String: String] else {
            throw ReleaseNotesParserError.yamlMissingLocales(url)
        }
        var locales: [String: String] = [:]
        var sourceFiles: [String: URL] = [:]
        for (key, value) in rawLocales {
            guard let resolved = mapper.resolve(key) else { continue }
            locales[resolved] = value
            sourceFiles[resolved] = url
        }
        return ParsedReleaseNotes(version: version, locales: locales, sourceFiles: sourceFiles, sourceDescription: url.path)
    }
}
