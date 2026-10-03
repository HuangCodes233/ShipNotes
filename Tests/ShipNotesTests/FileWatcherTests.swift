import Foundation
import Testing
@testable import ShipNotes

@Suite("FileWatcher")
struct FileWatcherTests {
    private let root = URL(fileURLWithPath: "/tmp/shipnotes-fixtures/project")

    @Test func sourceEditsTriggerAReload() {
        #expect(
            FileWatcher.isRelevantChange(
                path: "/tmp/shipnotes-fixtures/project/fastlane/metadata/en-US/release_notes.txt", root: root))
        #expect(FileWatcher.isRelevantChange(path: "/tmp/shipnotes-fixtures/project/CHANGELOG.md", root: root))
        #expect(FileWatcher.isRelevantChange(path: "/tmp/shipnotes-fixtures/project", root: root))
    }

    @Test func buildGitAndEditorChurnIsIgnored() {
        #expect(!FileWatcher.isRelevantChange(path: "/tmp/shipnotes-fixtures/project/.git/index", root: root))
        #expect(!FileWatcher.isRelevantChange(path: "/tmp/shipnotes-fixtures/project/.git", root: root))
        #expect(
            !FileWatcher.isRelevantChange(path: "/tmp/shipnotes-fixtures/project/.build/debug/ShipNotes.o", root: root))
        #expect(
            !FileWatcher.isRelevantChange(path: "/tmp/shipnotes-fixtures/project/node_modules/x/index.js", root: root))
        #expect(
            !FileWatcher.isRelevantChange(path: "/tmp/shipnotes-fixtures/project/DerivedData/Logs/a.log", root: root))
        #expect(!FileWatcher.isRelevantChange(path: "/tmp/shipnotes-fixtures/project/notes/.DS_Store", root: root))
        #expect(!FileWatcher.isRelevantChange(path: "/tmp/shipnotes-fixtures/project/notes/en.md.swp", root: root))
    }
}
