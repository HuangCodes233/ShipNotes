import Foundation

/// Comma-separated App Store keywords plus notable What's New lines.
enum AppleAdsKeywordSeed {
    static func phrases(
        keywords: String,
        whatsNew: String,
        appName: String? = nil
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func append(_ raw: String) {
            let trimmed =
                raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "•-*"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2, trimmed.count <= 80 else { return }
            let key = trimmed.lowercased()
            if let appName, key == appName.lowercased() { return }
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }

        for part in keywords.split(whereSeparator: { $0 == "," || $0 == "、" || $0 == ";" }) {
            append(String(part))
        }

        for line in whatsNew.split(whereSeparator: \.isNewline) {
            let cleaned = String(line)
                .replacingOccurrences(of: #"^[\s•\-\*]+"#, with: "", options: .regularExpression)
            if cleaned.count <= 40 {
                append(cleaned)
            } else {
                for word in cleaned.split(separator: " ") where word.count >= 4 {
                    append(String(word))
                }
            }
        }

        return Array(result.prefix(25))
    }
}
