import Foundation

struct DiffLine: Hashable, Identifiable {
    enum Kind: Hashable { case unchanged, added, removed }
    let id = UUID()
    let kind: Kind
    let text: String

    static func == (lhs: DiffLine, rhs: DiffLine) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.text == rhs.text
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(kind)
        hasher.combine(text)
    }
}

struct DiffEngine {
    func diff(old: String, new: String) -> [DiffLine] {
        if old == new {
            return splitLines(old).map { DiffLine(kind: .unchanged, text: $0) }
        }
        let oldLines = splitLines(old)
        let newLines = splitLines(new)

        // Like summary(), match the identical head and tail directly and run
        // the quadratic DP only on the edited middle: edits touch one region,
        // so per-keystroke recomputes stay cheap even for long documents.
        var prefix = 0
        while prefix < min(oldLines.count, newLines.count), oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        var oldEnd = oldLines.count
        var newEnd = newLines.count
        while oldEnd > prefix, newEnd > prefix, oldLines[oldEnd - 1] == newLines[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        let unchangedHead = oldLines[..<prefix].map { DiffLine(kind: .unchanged, text: $0) }
        let unchangedTail = oldLines[oldEnd...].map { DiffLine(kind: .unchanged, text: $0) }
        return unchangedHead
            + diffCore(oldLines: Array(oldLines[prefix..<oldEnd]), newLines: Array(newLines[prefix..<newEnd]))
            + unchangedTail
    }

    func summary(old: String, new: String) -> DiffSummary {
        if old == new {
            return DiffSummary(added: 0, removed: 0, unchanged: splitLines(old).count)
        }
        let oldLines = splitLines(old)
        let newLines = splitLines(new)

        // Editing usually leaves most lines unchanged. Matching ends can be
        // counted directly when only the LCS length (not its alignment) matters.
        var prefix = 0
        while prefix < min(oldLines.count, newLines.count), oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        var oldEnd = oldLines.count
        var newEnd = newLines.count
        while oldEnd > prefix, newEnd > prefix, oldLines[oldEnd - 1] == newLines[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        let unchanged = prefix + (oldLines.count - oldEnd) + commonLineCount(
            oldLines[prefix..<oldEnd], newLines[prefix..<newEnd]
        )
        return DiffSummary(
            added: newLines.count - unchanged,
            removed: oldLines.count - unchanged,
            unchanged: unchanged
        )
    }

    /// Summary counts need one DP row, not a full table or UUID-bearing DiffLines.
    /// The detailed diff keeps its existing backtracking and tie-breaking order.
    private func commonLineCount(_ lhs: ArraySlice<String>, _ rhs: ArraySlice<String>) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let columns = lhs.count <= rhs.count ? lhs : rhs
        let rows = lhs.count <= rhs.count ? rhs : lhs
        var lengths = Array(repeating: 0, count: columns.count + 1)
        for line in rows {
            var diagonal = 0
            for (offset, candidate) in columns.enumerated() {
                let index = offset + 1
                let previous = lengths[index]
                lengths[index] = line == candidate ? diagonal + 1 : max(previous, lengths[index - 1])
                diagonal = previous
            }
        }
        return lengths[columns.count]
    }

    private func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        return text.components(separatedBy: .newlines)
    }

    /// Full O(N×M) LCS with backtracking, run only on the edited middle.
    private func diffCore(oldLines: [String], newLines: [String]) -> [DiffLine] {
        let n = oldLines.count
        let m = newLines.count
        if n == 0 { return newLines.map { DiffLine(kind: .added, text: $0) } }
        if m == 0 { return oldLines.map { DiffLine(kind: .removed, text: $0) } }

        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0..<n {
            for j in 0..<m {
                if oldLines[i] == newLines[j] {
                    table[i + 1][j + 1] = table[i][j] + 1
                } else {
                    table[i + 1][j + 1] = max(table[i][j + 1], table[i + 1][j])
                }
            }
        }

        var result: [DiffLine] = []
        var i = n, j = m
        while i > 0 && j > 0 {
            if oldLines[i - 1] == newLines[j - 1] {
                result.append(DiffLine(kind: .unchanged, text: oldLines[i - 1]))
                i -= 1; j -= 1
            } else if table[i - 1][j] >= table[i][j - 1] {
                result.append(DiffLine(kind: .removed, text: oldLines[i - 1]))
                i -= 1
            } else {
                result.append(DiffLine(kind: .added, text: newLines[j - 1]))
                j -= 1
            }
        }
        while i > 0 { result.append(DiffLine(kind: .removed, text: oldLines[i - 1])); i -= 1 }
        while j > 0 { result.append(DiffLine(kind: .added, text: newLines[j - 1])); j -= 1 }
        return result.reversed()
    }
}
