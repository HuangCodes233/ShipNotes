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

    func validate(text: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            issues.append(.init(severity: .error, message: L("Release notes cannot be empty")))
            return issues
        }

        if text.count > Self.whatsNewCharacterLimit {
            issues.append(.init(
                severity: .error,
                message: L("Exceeds App Store limit of %1$d characters (currently %2$d)", Self.whatsNewCharacterLimit, text.count)
            ))
        }

        if containsMarkdown(text) {
            issues.append(.init(
                severity: .warning,
                message: L("Detected markdown syntax. App Store renders release notes as plain text."),
                isMarkdown: true
            ))
        }

        return issues
    }

    func containsMarkdown(_ text: String) -> Bool {
        let inlinePatterns = [
            #"\*\*[^*]+\*\*"#,
            #"__[^_]+__"#,
            #"\[[^\]]+\]\([^)]+\)"#,
            #"`[^`]+`"#,
        ]
        for pattern in inlinePatterns where text.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        for line in text.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil { return true }
            if stripped.hasPrefix("> ") { return true }
        }
        return false
    }

    func stripMarkdownToPlainText(_ text: String) -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            var l = line
            l = l.replacingOccurrences(of: #"^\s*#{1,6}\s+"#, with: "", options: .regularExpression)
            l = l.replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "• ", options: .regularExpression)
            l = l.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            l = l.replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
            l = l.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
            l = l.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            lines.append(l)
        }
        return lines.joined(separator: "\n")
    }
}
