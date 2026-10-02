import Testing
@testable import ShipNotes

@Suite("DiffEngine")
struct DiffEngineTests {
    let engine = DiffEngine()

    @Test func identicalTextHasNoChanges() {
        let lines = engine.diff(old: "hello\nworld", new: "hello\nworld")
        #expect(lines.allSatisfy { $0.kind == .unchanged })
        #expect(engine.summary(old: "x", new: "x").hasChanges == false)
    }

    @Test func newLineCountsAsAddition() {
        let lines = engine.diff(old: "a\nb", new: "a\nb\nc")
        #expect(lines.contains { $0.kind == .added && $0.text == "c" })
    }

    @Test func removedLineCountsAsRemoval() {
        let lines = engine.diff(old: "a\nb\nc", new: "a\nc")
        #expect(lines.contains { $0.kind == .removed && $0.text == "b" })
    }

    @Test func replacementShowsBothAddAndRemove() {
        let summary = engine.summary(old: "a\nb", new: "a\nB")
        #expect(summary.added == 1)
        #expect(summary.removed == 1)
        #expect(summary.unchanged == 1)
    }

    @Test func handlesEmptyOldText() {
        let lines = engine.diff(old: "", new: "a\nb")
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.kind == .added })
    }

    @Test func summaryMatchesDetailedDiffWithRepeatedAndEmptyLines() {
        // Exhaust all short documents over a small alphabet to exercise LCS
        // ties, repeated lines and matching ends without assuming an alignment.
        var documents = [""]
        var sequences: [[String]] = [[]]
        for _ in 0..<3 {
            sequences = sequences.flatMap { prefix in ["a", "b", ""].map { prefix + [$0] } }
            documents.append(contentsOf: sequences.map { $0.joined(separator: "\n") })
        }
        documents.append(contentsOf: ["a\r\nb\r\n", "你好\n🙂\n", "a\u{2028}b", "\n\n\n"])
        for old in documents {
            for new in documents {
                let lines = engine.diff(old: old, new: new)
                let summary = engine.summary(old: old, new: new)
                #expect(summary.added == lines.count(where: { $0.kind == .added }))
                #expect(summary.removed == lines.count(where: { $0.kind == .removed }))
                #expect(summary.unchanged == lines.count(where: { $0.kind == .unchanged }))
            }
        }
    }

    @Test func summaryHandlesLargeMostlyUnchangedDocument() {
        let original = (0..<5_000).map { "Line \($0)" }
        var edited = original
        edited[2_500] = "Replacement"
        let summary = engine.summary(old: original.joined(separator: "\n"), new: edited.joined(separator: "\n"))
        #expect(summary.added == 1)
        #expect(summary.removed == 1)
        #expect(summary.unchanged == 4_999)
    }
}
