import Foundation

enum FileScannerUtils {
    static func shouldSkip(_ url: URL, isDirectory: Bool) -> Bool {
        guard isDirectory else { return false }
        let normalized = url.lastPathComponent.lowercased().filter { $0.isLetter || $0.isNumber }
        if ["git", "build", "deriveddata", "nodemodules", "swiftpm", "pods"].contains(normalized) {
            return true
        }
        return ["xcodeproj", "xcworkspace", "xcassets", "app", "framework", "bundle"].contains(url.pathExtension.lowercased())
    }

    /// Conventional App Store metadata folder paths under a project/root directory.
    static func metadataFolderCandidates(under root: URL) -> [URL] {
        [
            root.appending(path: "fastlane").appending(path: "metadata"),
            root.appending(path: "fastlane").appending(path: "Metadata"),
            root.appending(path: "AppStore").appending(path: "metadata"),
            root.appending(path: "AppStore").appending(path: "Metadata"),
            root.appending(path: "metadata"),
            root.appending(path: "Metadata")
        ]
    }

    /// First existing metadata folder under `root`, or `nil` if none exist.
    static func preferredMetadataFolder(in root: URL) -> URL? {
        metadataFolderCandidates(under: root).first(where: isDirectory)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Single entry point for reading a UTF-8 text file for parsing.
    ///
    /// Normalizes line endings (CRLF / lone CR → LF) so line-based parsers
    /// never see doubled blank lines from Windows-saved files, and strips a
    /// UTF-8 BOM so the first heading / YAML key isn't prefixed with an
    /// invisible character that defeats `hasPrefix` checks.
    static func readText(at url: URL) throws -> String {
        var text = try String(contentsOf: url, encoding: .utf8)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
