import CryptoKit
import Foundation
import ImageIO

enum ScreenshotScannerError: Error, LocalizedError, Sendable {
    case folderUnreadable(URL)
    case noImagesFound(URL)

    var errorDescription: String? {
        switch self {
        case .folderUnreadable(let url): L("Cannot read screenshot folder at %@", url.path)
        case .noImagesFound(let url): L("No screenshots found in %@", url.lastPathComponent)
        }
    }
}

struct ScreenshotScanner {
    private let mapper = LocaleMapper()
    private let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff"]
    private let maxDepth = 6
    /// Root discovery samples the same images the main walk reads; remember
    /// their sizes for the duration of one scan instead of reopening them.
    private let sizeCache = ImageSizeCache()

    func scan(url: URL) throws -> ScreenshotScan {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw ScreenshotScannerError.folderUnreadable(url)
        }

        let resolvedRoot = resolveScanRoot(from: url)
        try Task.checkCancellation()
        let scanRoot = resolvedRoot.url
        let rootPath = scanRoot.standardizedFileURL.path
        var found: [(asset: ScreenshotAsset, fileSize: Int?)] = []
        var skipped = 0

        func walk(_ folder: URL, depth: Int) throws {
            guard depth <= maxDepth else { return }
            // Refreshing, or picking another folder, cancels this scan; stop
            // walking a large tree instead of finishing work nobody will use.
            try Task.checkCancellation()
            for entry in entries(in: folder) {
                if FileScannerUtils.shouldSkip(entry.url, isDirectory: entry.isDirectory) { continue }
                if entry.isDirectory {
                    try walk(entry.url, depth: depth + 1)
                    continue
                }
                let child = entry.url
                guard supportedExtensions.contains(child.pathExtension.lowercased()) else { continue }
                guard let size = imageSize(at: child) else {
                    skipped += 1
                    continue
                }
                let slot = ScreenshotDeviceSlot.matching(size: size)
                let locale = detectLocale(for: child, root: url)
                found.append(
                    (
                        ScreenshotAsset(
                            url: child,
                            relativePath: relativePath(for: child, rootPath: rootPath),
                            size: size,
                            locale: locale,
                            deviceSlot: slot,
                            status: slot == nil ? .unsupportedSize : .ready,
                            contentHash: nil
                        ),
                        entry.fileSize
                    ))
            }
        }

        try walk(scanRoot, depth: 0)

        guard !found.isEmpty else {
            throw ScreenshotScannerError.noImagesFound(url)
        }

        let assets = try hashingPossibleDuplicates(found)
        return ScreenshotScan(
            inputRoot: url,
            root: scanRoot,
            sourceKind: resolvedRoot.kind,
            assets: assets.sorted(by: { $0.relativePath < $1.relativePath }),
            skippedCount: skipped
        )
    }

    /// The content hash only feeds duplicate detection. Identical files have
    /// identical byte sizes, so only files sharing (slot, byte size) are read
    /// and hashed — not every multi-MB image on every scan. The locale is
    /// left out on purpose: AI matching can move an unassigned file into a
    /// locale later, and it still needs a hash to be flagged as a duplicate.
    private func hashingPossibleDuplicates(
        _ found: [(asset: ScreenshotAsset, fileSize: Int?)]
    ) throws -> [ScreenshotAsset] {
        let groups = Dictionary(grouping: found.indices) { index -> String in
            let (asset, fileSize) = found[index]
            return "\(asset.deviceSlot?.rawValue ?? "")|\(fileSize.map(String.init) ?? "unknown-\(index)")"
        }
        var assets = found.map(\.asset)
        for indices in groups.values where indices.count > 1 {
            for index in indices {
                try Task.checkCancellation()
                let asset = assets[index]
                assets[index] = ScreenshotAsset(
                    url: asset.url,
                    relativePath: asset.relativePath,
                    size: asset.size,
                    locale: asset.locale,
                    deviceSlot: asset.deviceSlot,
                    status: asset.status,
                    contentHash: fileHash(at: asset.url)
                )
            }
        }
        return assets
    }

    private static let listingKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]

    /// One directory listing with the type and size prefetched, instead of a
    /// separate `fileExists` call per entry.
    private func entries(in folder: URL) -> [(url: URL, isDirectory: Bool, fileSize: Int?)] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(Self.listingKeys)
            )) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Self.listingKeys)
            var isDirectory = values?.isDirectory ?? false
            if values?.isSymbolicLink == true {
                // Keep following symlinked folders, as `fileExists` did.
                var isDir: ObjCBool = false
                isDirectory = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
            return (url, isDirectory, values?.fileSize)
        }
        .sorted { $0.url.path < $1.url.path }
    }

    private func resolveScanRoot(from url: URL) -> (url: URL, kind: ScreenshotScanSourceKind) {
        let candidates = screenshotRootCandidates(in: url)
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.url.path.count != rhs.url.path.count { return lhs.url.path.count < rhs.url.path.count }
            return lhs.url.path < rhs.url.path
        }

        guard let best = sorted.first, best.score >= 90 else {
            return (url, .fallbackProjectScan)
        }
        if best.url.standardizedFileURL == url.standardizedFileURL {
            return (url, .directFolder)
        }
        return (best.url, .discoveredFolder)
    }

    private func screenshotRootCandidates(in root: URL) -> [(url: URL, score: Int)] {
        let fm = FileManager.default
        var candidates: [(URL, Int)] = []

        func walk(_ folder: URL, depth: Int) {
            guard depth <= 4, !Task.isCancelled else { return }
            var folderIsDir: ObjCBool = false
            fm.fileExists(atPath: folder.path, isDirectory: &folderIsDir)
            guard folderIsDir.boolValue, !FileScannerUtils.shouldSkip(folder, isDirectory: true) else { return }

            let score = candidateScore(for: folder, inputRoot: root)
            if score > 0 {
                candidates.append((folder, score))
            }

            for entry in entries(in: folder) where entry.isDirectory {
                walk(entry.url, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return candidates
    }

    private func candidateScore(for folder: URL, inputRoot: URL) -> Int {
        let path = folder.standardizedFileURL.path.lowercased()
        let name = folder.lastPathComponent.lowercased()
        let components = folder.standardizedFileURL.pathComponents.map { $0.lowercased() }
        var score = 0

        if folder.standardizedFileURL == inputRoot.standardizedFileURL {
            score += 10
        }
        if name.contains("screenshot") || name.contains("screenshots") {
            score += 150
        }
        if path.contains("/appstore/screenshots") || path.contains("/appstore/screenshot") {
            score += 120
        }
        if path.contains("/fastlane/screenshots") {
            score += 120
        }
        if components.contains("appstore") {
            score += 40
        }
        if components.contains("fastlane") {
            score += 35
        }
        if components.contains("metadata") {
            score += 20
        }
        if components.contains("upload"), path.contains("screenshot") {
            score += 250
        }
        if mapper.resolve(folder.lastPathComponent) != nil {
            score += 20
        }

        let sample = imageSample(in: folder, maxDepth: 2)
        score += min(sample.total * 4, 60)
        score += min(sample.accepted * 8, 80)
        score += min(sample.localeHints * 4, 30)
        return score
    }

    private func imageSample(in folder: URL, maxDepth: Int) -> (total: Int, accepted: Int, localeHints: Int) {
        var total = 0
        var accepted = 0
        var localeHints = 0

        func walk(_ current: URL, depth: Int) {
            guard depth <= maxDepth, total < 80, !Task.isCancelled else { return }
            for entry in entries(in: current) {
                // The cap applies per image, not only on entering a folder, so
                // a flat folder of hundreds of images is sampled, not read.
                guard total < 80 else { return }
                let child = entry.url
                if FileScannerUtils.shouldSkip(child, isDirectory: entry.isDirectory) { continue }
                if entry.isDirectory {
                    if mapper.resolve(child.lastPathComponent) != nil {
                        localeHints += 1
                    }
                    walk(child, depth: depth + 1)
                    continue
                }
                guard supportedExtensions.contains(child.pathExtension.lowercased()) else { continue }
                total += 1
                if let size = imageSize(at: child), ScreenshotDeviceSlot.matching(size: size) != nil {
                    accepted += 1
                }
            }
        }

        walk(folder, depth: 0)
        return (total, accepted, localeHints)
    }

    private func imageSize(at url: URL) -> ScreenshotPixelSize? {
        if let cached = sizeCache.sizes[url] { return cached }
        let size = readImageSize(at: url)
        sizeCache.sizes[url] = .some(size)
        return size
    }

    private func readImageSize(at url: URL) -> ScreenshotPixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return ScreenshotPixelSize(width: width, height: height)
    }

    private func fileHash(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func detectLocale(for file: URL, root: URL) -> String? {
        let components = Array(file.standardizedFileURL.pathComponents)
        let rootComponents = Array(root.standardizedFileURL.pathComponents)
        let relativeComponents = components.dropFirst(rootComponents.count)

        for token in LocaleMapper.pathLocaleHints(Array(relativeComponents)) {
            if let resolved = mapper.resolve(token) {
                return resolved
            }
        }
        return nil
    }

    private func relativePath(for file: URL, rootPath: String) -> String {
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return file.lastPathComponent }
        let relative = String(path.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? file.lastPathComponent : relative
    }

}

/// Per-scan memo of image dimensions (`nil` = unreadable). A scanner value is
/// created for one scan and used from one thread.
private final class ImageSizeCache {
    var sizes: [URL: ScreenshotPixelSize?] = [:]
}
