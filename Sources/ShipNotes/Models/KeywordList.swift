import Foundation

/// Editing rules for the comma-separated App Store keywords field.
///
/// The 100-character limit counts separators, so tags are joined with a bare
/// comma (the App Store convention). Joining with ", " made removing one tag
/// add a space per remaining tag and could push a tightly packed field over
/// the limit.
enum KeywordList {
    static let separator = ","

    static func tags(in text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Removes only the tag at `index`; a repeated keyword keeps its twin.
    static func removing(at index: Int, from text: String) -> String {
        var current = tags(in: text)
        guard current.indices.contains(index) else { return text }
        current.remove(at: index)
        return current.joined(separator: separator)
    }

    /// Adds one keyword or a pasted comma-separated list, skipping
    /// case-insensitive duplicates. Returns `nil` when the input is empty.
    static func adding(_ input: String, to text: String) -> String? {
        let additions = tags(in: input)
        guard !additions.isEmpty else { return nil }
        var current = tags(in: text)
        for tag in additions where !current.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            current.append(tag)
        }
        return current.joined(separator: separator)
    }
}
