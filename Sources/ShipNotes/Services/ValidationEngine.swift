import Foundation

struct ValidationIssue: Hashable, Identifiable, Sendable {
    enum Severity: Hashable, Sendable { case warning, error }
    var id: Self { self }
    let severity: Severity
    let message: String
    var isMarkdown: Bool = false
}

struct ValidationEngine {
    static let whatsNewCharacterLimit = 4000

    // Precompiled once: `range(of:options:.regularExpression)` recompiles the
    // pattern on every call, and these run on every keystroke per field.
    private static let inlineMarkdownPatterns: [NSRegularExpression] = [
        #"\*\*[^*]+\*\*"#,
        #"__[^_]+__"#,
        #"\[[^\]]+\]\([^)]+\)"#,
        #"`[^`]+`"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    private static let stripPatterns: [(NSRegularExpression, String)] = [
        (#"^\s*#{1,6}\s+"#, ""),
        (#"^\s*[-*+]\s+"#, "• "),
        (#"\*\*([^*]+)\*\*"#, "$1"),
        (#"__([^_]+)__"#, "$1"),
        (#"`([^`]+)`"#, "$1"),
        (#"\[([^\]]+)\]\([^)]+\)"#, "$1"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    private static let headingPattern = try! NSRegularExpression(pattern: #"^#{1,6}\s"#)

    func validate(text: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            issues.append(.init(severity: .error, message: L("Release notes cannot be empty")))
            return issues
        }

        if text.count > Self.whatsNewCharacterLimit {
            issues.append(
                .init(
                    severity: .error,
                    message: L(
                        "Exceeds App Store limit of %1$d characters (currently %2$d)", Self.whatsNewCharacterLimit,
                        text.count)
                ))
        }

        if containsMarkdown(text) {
            issues.append(
                .init(
                    severity: .warning,
                    message: L("Detected markdown syntax. App Store renders release notes as plain text."),
                    isMarkdown: true
                ))
        }

        return issues
    }

    func containsMarkdown(_ text: String) -> Bool {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for pattern in Self.inlineMarkdownPatterns
        where pattern.firstMatch(in: text, range: fullRange) != nil {
            return true
        }
        for line in text.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("> ") { return true }
            let lineRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
            if Self.headingPattern.firstMatch(in: stripped, range: lineRange) != nil { return true }
        }
        return false
    }

    func stripMarkdownToPlainText(_ text: String) -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            var l = line
            for (pattern, template) in Self.stripPatterns {
                let range = NSRange(l.startIndex..<l.endIndex, in: l)
                l = pattern.stringByReplacingMatches(in: l, range: range, withTemplate: template)
            }
            lines.append(l)
        }
        return lines.joined(separator: "\n")
    }
}
