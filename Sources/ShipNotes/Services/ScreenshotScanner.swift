import Foundation
import CryptoKit
import ImageIO

struct ScreenshotPixelSize: Hashable, Sendable, Comparable {
    let width: Int
    let height: Int

    var orientation: ScreenshotOrientation {
        if width == height { return .square }
        return width > height ? .landscape : .portrait
    }

    var displayName: String { "\(width) x \(height)" }

    var normalized: ScreenshotPixelSize {
        width >= height
            ? ScreenshotPixelSize(width: width, height: height)
            : ScreenshotPixelSize(width: height, height: width)
    }

    static func < (lhs: ScreenshotPixelSize, rhs: ScreenshotPixelSize) -> Bool {
        if lhs.width != rhs.width { return lhs.width < rhs.width }
        return lhs.height < rhs.height
    }
}

enum ScreenshotOrientation: String, Hashable, Sendable {
    case portrait
    case landscape
    case square

    var displayName: String {
        switch self {
        case .portrait: L("Portrait")
        case .landscape: L("Landscape")
        case .square: L("Square")
        }
    }
}

enum ScreenshotDeviceSlot: String, CaseIterable, Identifiable, Hashable, Sendable {
    case iPhone69
    case iPhone65
    case iPad13
    case mac
    case appleTV
    case visionPro
    case appleWatch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iPhone69: "iPhone 6.9\""
        case .iPhone65: "iPhone 6.5\""
        case .iPad13: "iPad 13\""
        case .mac: "Mac"
        case .appleTV: "Apple TV"
        case .visionPro: "Apple Vision Pro"
        case .appleWatch: "Apple Watch"
        }
    }

    var platform: String {
        switch self {
        case .iPhone69, .iPhone65, .iPad13: "iOS"
        case .mac: "macOS"
        case .appleTV: "tvOS"
        case .visionPro: "visionOS"
        case .appleWatch: "watchOS"
        }
    }

    var requiredCopy: String {
        switch self {
        case .iPhone69, .iPhone65: L("Required for iPhone apps")
        case .iPad13: L("Required if app runs on iPad")
        case .mac: L("Required for Mac apps")
        case .appleTV: L("Required for Apple TV apps")
        case .visionPro: L("Required for Apple Vision Pro apps")
        case .appleWatch: L("Required for Apple Watch apps")
        }
    }

    var appStoreConnectDisplayType: String {
        switch self {
        case .iPhone69: "APP_IPHONE_67"
        case .iPhone65: "APP_IPHONE_65"
        case .iPad13: "APP_IPAD_PRO_3GEN_129"
        case .mac: "APP_DESKTOP"
        case .appleTV: "APP_APPLE_TV"
        case .visionPro: "APP_APPLE_VISION_PRO"
        case .appleWatch: "APP_WATCH_SERIES_10"
        }
    }

    var acceptedSizes: [ScreenshotPixelSize] {
        switch self {
        case .iPhone69:
            [
                ScreenshotPixelSize(width: 1260, height: 2736),
                ScreenshotPixelSize(width: 2736, height: 1260),
                ScreenshotPixelSize(width: 1290, height: 2796),
                ScreenshotPixelSize(width: 2796, height: 1290),
                ScreenshotPixelSize(width: 1320, height: 2868),
                ScreenshotPixelSize(width: 2868, height: 1320)
            ]
        case .iPhone65:
            [
                ScreenshotPixelSize(width: 1242, height: 2688),
                ScreenshotPixelSize(width: 2688, height: 1242),
                ScreenshotPixelSize(width: 1284, height: 2778),
                ScreenshotPixelSize(width: 2778, height: 1284)
            ]
        case .iPad13:
            [
                ScreenshotPixelSize(width: 2064, height: 2752),
                ScreenshotPixelSize(width: 2752, height: 2064),
                ScreenshotPixelSize(width: 2048, height: 2732),
                ScreenshotPixelSize(width: 2732, height: 2048)
            ]
        case .mac:
            [
                ScreenshotPixelSize(width: 1280, height: 800),
                ScreenshotPixelSize(width: 1440, height: 900),
                ScreenshotPixelSize(width: 2560, height: 1600),
                ScreenshotPixelSize(width: 2880, height: 1800)
            ]
        case .appleTV:
            [
                ScreenshotPixelSize(width: 1920, height: 1080),
                ScreenshotPixelSize(width: 3840, height: 2160)
            ]
        case .visionPro:
            [ScreenshotPixelSize(width: 3840, height: 2160)]
        case .appleWatch:
            [
                ScreenshotPixelSize(width: 422, height: 514),
                ScreenshotPixelSize(width: 410, height: 502),
                ScreenshotPixelSize(width: 416, height: 496),
                ScreenshotPixelSize(width: 396, height: 484),
                ScreenshotPixelSize(width: 368, height: 448),
                ScreenshotPixelSize(width: 312, height: 390)
            ]
        }
    }

    static func matching(size: ScreenshotPixelSize) -> ScreenshotDeviceSlot? {
        Self.allCases.first { $0.acceptedSizes.contains(size) }
    }

    static func matching(displayType: String) -> ScreenshotDeviceSlot? {
        Self.allCases.first { $0.appStoreConnectDisplayType == displayType }
    }
}

struct ScreenshotSlotRequirement: Identifiable, Hashable, Sendable {
    let slots: [ScreenshotDeviceSlot]

    var id: String {
        slots.map(\.rawValue).joined(separator: "+")
    }

    var displayName: String {
        slots.map(\.displayName).joined(separator: " / ")
    }

    var requiredCopy: String {
        guard slots.count != 1 else { return slots[0].requiredCopy }
        return L("Provide at least one of: %@", displayName)
    }

    func contains(_ slot: ScreenshotDeviceSlot) -> Bool {
        slots.contains(slot)
    }

    func isSatisfied(by assets: [ScreenshotAsset]) -> Bool {
        assets.contains { asset in
            guard let slot = asset.deviceSlot else { return false }
            return slots.contains(slot)
        }
    }

    static func oneOf(_ slots: [ScreenshotDeviceSlot]) -> ScreenshotSlotRequirement {
        ScreenshotSlotRequirement(slots: slots)
    }

    static func exact(_ slot: ScreenshotDeviceSlot) -> ScreenshotSlotRequirement {
        ScreenshotSlotRequirement(slots: [slot])
    }

    /// Device slots App Store Connect expects for a platform.
    /// iPad is optional and only required when the binary actually supports it.
    /// Kept as a pure function so AppState only supplies platform + iPad flags.
    static func groups(platform: String, requiresIPad: Bool) -> [ScreenshotSlotRequirement] {
        let value = platform.lowercased()
        if value.contains("mac") { return [.exact(.mac)] }
        if value.contains("tv") { return [.exact(.appleTV)] }
        if value.contains("vision") { return [.exact(.visionPro)] }
        if value.contains("watch") { return [.exact(.appleWatch)] }
        var groups: [ScreenshotSlotRequirement] = [.oneOf([.iPhone69, .iPhone65])]
        if requiresIPad {
            groups.append(.exact(.iPad13))
        }
        return groups
    }
}

enum ScreenshotScanSourceKind: Hashable, Sendable {
    case directFolder
    case discoveredFolder
    case fallbackProjectScan

    var displayName: String {
        switch self {
        case .directFolder: L("Selected folder")
        case .discoveredFolder: L("Auto-discovered screenshot folder")
        case .fallbackProjectScan: L("Project scan")
        }
    }
}

enum ScreenshotAssetStatus: Hashable, Sendable {
    case ready
    case unsupportedSize

    var displayName: String {
        switch self {
        case .ready: L("Ready")
        case .unsupportedSize: L("Unsupported Size")
        }
    }
}

struct ScreenshotAsset: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let relativePath: String
    let size: ScreenshotPixelSize
    let locale: String?
    let deviceSlot: ScreenshotDeviceSlot?
    let status: ScreenshotAssetStatus
    let contentHash: String?
}

struct ScreenshotLocaleGroup: Identifiable, Hashable, Sendable {
    var id: String { isUnassigned ? ScreenshotScan.unassignedLocaleID : locale }
    let locale: String
    let assets: [ScreenshotAsset]
    let isUnassigned: Bool

    func count(for slot: ScreenshotDeviceSlot) -> Int {
        assets.filter { $0.deviceSlot == slot }.count
    }
}

struct ScreenshotScan: Hashable, Sendable {
    let inputRoot: URL
    let root: URL
    let sourceKind: ScreenshotScanSourceKind
    let assets: [ScreenshotAsset]
    let skippedCount: Int
    let readyCount: Int
    let unsupportedCount: Int
    let localeGroups: [ScreenshotLocaleGroup]

    static let unassignedLocaleID = "__shipnotes_unassigned__"
    static var unassignedLocaleDisplayName: String { L("Unassigned") }

    init(inputRoot: URL, root: URL, sourceKind: ScreenshotScanSourceKind, assets: [ScreenshotAsset], skippedCount: Int) {
        self.inputRoot = inputRoot
        self.root = root
        self.sourceKind = sourceKind
        self.assets = assets
        self.skippedCount = skippedCount

        var ready = 0
        var unsupported = 0
        for asset in assets {
            if asset.status == .ready { ready += 1 }
            else if asset.status == .unsupportedSize { unsupported += 1 }
        }
        self.readyCount = ready
        self.unsupportedCount = unsupported

        let grouped = Dictionary(grouping: assets) { $0.locale ?? Self.unassignedLocaleID }
        self.localeGroups = grouped
            .map { locale, assets in
                let isUnassigned = locale == Self.unassignedLocaleID
                return ScreenshotLocaleGroup(
                    locale: isUnassigned ? Self.unassignedLocaleDisplayName : locale,
                    assets: assets.sorted(by: { $0.relativePath < $1.relativePath }),
                    isUnassigned: isUnassigned
                )
            }
            .sorted { lhs, rhs in
                if lhs.isUnassigned != rhs.isUnassigned { return !lhs.isUnassigned }
                if lhs.locale == "en-US" { return true }
                if rhs.locale == "en-US" { return false }
                return lhs.locale.localizedStandardCompare(rhs.locale) == .orderedAscending
            }
    }

    func missingRequirements(
        for locale: String,
        requiredGroups: [ScreenshotSlotRequirement]
    ) -> [ScreenshotSlotRequirement] {
        guard locale != Self.unassignedLocaleDisplayName else { return [] }
        let groupAssets = assets.filter { ($0.locale ?? Self.unassignedLocaleDisplayName) == locale }
        return requiredGroups.filter { requirement in
            !requirement.isSatisfied(by: groupAssets)
        }
    }

    func issues(
        expectedSlots: [ScreenshotDeviceSlot],
        localeGroups groupsOverride: [ScreenshotLocaleGroup]? = nil
    ) -> [ScreenshotIssue] {
        issues(
            requiredGroups: expectedSlots.map(ScreenshotSlotRequirement.exact),
            localeGroups: groupsOverride
        )
    }

    func issues(
        requiredGroups: [ScreenshotSlotRequirement],
        localeGroups groupsOverride: [ScreenshotLocaleGroup]? = nil
    ) -> [ScreenshotIssue] {
        var issues: [ScreenshotIssue] = []
        let groups = groupsOverride ?? localeGroups

        for group in groups {
            if !group.isUnassigned {
                let missing = requiredGroups.filter { requirement in
                    !requirement.isSatisfied(by: group.assets)
                }
                for requirement in missing {
                    let detail = requirement.slots.count == 1
                        ? L("%1$@ is missing %2$@ screenshots.", group.locale, requirement.displayName)
                        : L("%1$@ is missing screenshots for one of: %2$@.", group.locale, requirement.displayName)
                    issues.append(ScreenshotIssue(
                        severity: .error,
                        title: L("Missing required screenshot size"),
                        detail: detail,
                        locale: group.locale,
                        slot: requirement.slots.first,
                        assetIDs: []
                    ))
                }

                for slot in ScreenshotDeviceSlot.allCases {
                    let count = group.count(for: slot)
                    if count > 10 {
                        issues.append(ScreenshotIssue(
                            severity: .error,
                            title: L("Too many screenshots"),
                            detail: L("%1$@ has %2$d screenshots for %3$@. App Store Connect allows up to 10.", group.locale, count, slot.displayName),
                            locale: group.locale,
                            slot: slot,
                            assetIDs: group.assets.filter { $0.deviceSlot == slot }.map(\.id)
                        ))
                    }
                }
            }
        }

        for asset in assets where asset.status == .unsupportedSize {
            issues.append(ScreenshotIssue(
                severity: .error,
                title: L("Unsupported screenshot size"),
                detail: L("%1$@ is %2$@, which does not match a known App Store screenshot size.", asset.url.lastPathComponent, asset.size.displayName),
                locale: asset.locale ?? Self.unassignedLocaleDisplayName,
                slot: nil,
                assetIDs: [asset.id]
            ))
        }

        let unassigned = assets.filter { $0.locale == nil }
        if !unassigned.isEmpty {
            issues.append(ScreenshotIssue(
                severity: .warning,
                title: L("Locale not detected"),
                detail: L("%d screenshot(s) are not inside a recognizable locale folder or filename. Put them in a locale folder like en-US or include the locale code in the filename.", unassigned.count),
                locale: Self.unassignedLocaleDisplayName,
                slot: nil,
                assetIDs: unassigned.map(\.id)
            ))
        }

        let duplicateGroups = Dictionary(grouping: assets.compactMap { asset -> (String, ScreenshotAsset)? in
            guard let hash = asset.contentHash else { return nil }
            let key = "\(asset.locale ?? "unassigned")|\(asset.deviceSlot?.rawValue ?? "unknown")|\(hash)"
            return (key, asset)
        }, by: \.0)

        for group in duplicateGroups.values {
            let duplicates = group.map(\.1)
            guard duplicates.count > 1 else { continue }
            let first = duplicates[0]
            issues.append(ScreenshotIssue(
                severity: .warning,
                title: L("Possible duplicate screenshots"),
                detail: L("%d screenshots look identical in %@.", duplicates.count, first.deviceSlot?.displayName ?? L("Unknown Size")),
                locale: first.locale ?? Self.unassignedLocaleDisplayName,
                slot: first.deviceSlot,
                assetIDs: duplicates.map(\.id)
            ))
        }

        return issues.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity.sortPriority < rhs.severity.sortPriority }
            return lhs.detail.localizedStandardCompare(rhs.detail) == .orderedAscending
        }
    }
}

enum ScreenshotIssueSeverity: Hashable, Sendable {
    case error
    case warning
    case info

    var sortPriority: Int {
        switch self {
        case .error: 0
        case .warning: 1
        case .info: 2
        }
    }

    var displayName: String {
        switch self {
        case .error: L("Error")
        case .warning: L("Warning")
        case .info: L("Info")
        }
    }
}

enum ScreenshotMoveDirection: Hashable, Sendable {
    case up
    case down
}

struct ScreenshotIssue: Identifiable, Hashable, Sendable {
    var id: String {
        [
            severity.displayName,
            title,
            locale ?? "",
            slot?.rawValue ?? "",
            assetIDs.joined(separator: ",")
        ].joined(separator: "|")
    }

    let severity: ScreenshotIssueSeverity
    let title: String
    let detail: String
    let locale: String?
    let slot: ScreenshotDeviceSlot?
    let assetIDs: [String]
}

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
                found.append((
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
        let urls = (try? FileManager.default.contentsOfDirectory(
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
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
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
