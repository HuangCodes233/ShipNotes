import Foundation

enum MinimalYAMLError: Error, LocalizedError {
    case malformed(String)

    var errorDescription: String? {
        if case .malformed(let msg) = self { return L("Malformed YAML: %@.", msg) }
        return nil
    }
}

/// Tiny YAML reader for the specific shape ShipNotes consumes:
///
///     version: 1.4.0
///     locales:
///       en-US: |
///         Fixed import issues and improved stability.
///       zh-Hans: |
///         修复导入问题，并提升稳定性。
///
/// Supports: top-level scalar `key: value`, nested map `key:` then indented
/// `subkey: value` or `subkey: |` followed by indented block scalar.
struct MinimalYAML {
    func parse(_ text: String) throws -> [String: Any] {
        var lines = text.components(separatedBy: .newlines)
        if let last = lines.last, last.isEmpty { lines.removeLast() }
        var index = 0
        return try parseMap(lines: lines, index: &index, baseIndent: 0)
    }

    private func parseMap(lines: [String], index: inout Int, baseIndent: Int) throws -> [String: Any] {
        var result: [String: Any] = [:]
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { index += 1; continue }
            // Whole-line comments and document markers are legal YAML and
            // carry no key/value — skip them instead of failing on the
            // missing ':' below.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed == "---" || trimmed == "..." { index += 1; continue }
            let indent = leadingSpaces(line)
            if indent < baseIndent { break }
            if indent > baseIndent {
                throw MinimalYAMLError.malformed("Unexpected indent at line \(index + 1)")
            }
            let content = line.dropFirst(indent)
            guard let colon = content.firstIndex(of: ":") else {
                throw MinimalYAMLError.malformed("Missing ':' at line \(index + 1)")
            }
            let key = String(content[..<colon]).trimmingCharacters(in: .whitespaces)
            var valuePart = String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            // Strip a trailing " # comment" from plain scalar values.
            if !valuePart.hasPrefix("\"") && !valuePart.hasPrefix("'"),
               let hash = valuePart.range(of: " #") {
                valuePart = String(valuePart[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            index += 1

            if valuePart == "|" || valuePart == "|-" || valuePart == ">" {
                let stripTrailingNewline = (valuePart == "|-")
                let block = readBlockScalar(lines: lines, index: &index, baseIndent: baseIndent)
                result[key] = stripTrailingNewline ? block.trimmingCharacters(in: .newlines) : block
            } else if valuePart.isEmpty {
                let childBase = nextNonBlankIndent(lines: lines, from: index)
                if let childBase, childBase > baseIndent {
                    result[key] = try parseMap(lines: lines, index: &index, baseIndent: childBase)
                } else {
                    result[key] = [String: Any]()
                }
            } else {
                result[key] = unquote(valuePart)
            }
        }
        return result
    }

    private func readBlockScalar(lines: [String], index: inout Int, baseIndent: Int) -> String {
        var content: [String] = []
        var blockIndent: Int? = nil
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                content.append("")
                index += 1
                continue
            }
            let indent = leadingSpaces(line)
            if indent <= baseIndent { break }
            if blockIndent == nil { blockIndent = indent }
            let strip = blockIndent ?? indent
            let trimmed = String(line.dropFirst(min(strip, indent)))
            content.append(trimmed)
            index += 1
        }
        while content.last == "" { content.removeLast() }
        return content.joined(separator: "\n")
    }

    private func nextNonBlankIndent(lines: [String], from start: Int) -> Int? {
        var i = start
        while i < lines.count {
            if !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                return leadingSpaces(lines[i])
            }
            i += 1
        }
        return nil
    }

    private func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 } else if ch == "\t" { count += 2 } else { break }
        }
        return count
    }

    private func unquote(_ value: String) -> String {
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
