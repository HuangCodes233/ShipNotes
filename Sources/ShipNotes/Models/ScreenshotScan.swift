import Foundation

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

    init(inputRoot: URL, root: URL, sourceKind: ScreenshotScanSourceKind, assets: [ScreenshotAsset], skippedCount: Int)
    {
        self.inputRoot = inputRoot
        self.root = root
        self.sourceKind = sourceKind
        self.assets = assets
        self.skippedCount = skippedCount

        var ready = 0
        var unsupported = 0
        for asset in assets {
            if asset.status == .ready { ready += 1 } else if asset.status == .unsupportedSize { unsupported += 1 }
        }
        self.readyCount = ready
        self.unsupportedCount = unsupported

        let grouped = Dictionary(grouping: assets) { $0.locale ?? Self.unassignedLocaleID }
        self.localeGroups =
            grouped
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
                    let detail =
                        requirement.slots.count == 1
                        ? L("%1$@ is missing %2$@ screenshots.", group.locale, requirement.displayName)
                        : L("%1$@ is missing screenshots for one of: %2$@.", group.locale, requirement.displayName)
                    issues.append(
                        ScreenshotIssue(
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
                        issues.append(
                            ScreenshotIssue(
                                severity: .error,
                                title: L("Too many screenshots"),
                                detail: L(
                                    "%1$@ has %2$d screenshots for %3$@. App Store Connect allows up to 10.",
                                    group.locale, count, slot.displayName),
                                locale: group.locale,
                                slot: slot,
                                assetIDs: group.assets.filter { $0.deviceSlot == slot }.map(\.id)
                            ))
                    }
                }
            }
        }

        for asset in assets where asset.status == .unsupportedSize {
            issues.append(
                ScreenshotIssue(
                    severity: .error,
                    title: L("Unsupported screenshot size"),
                    detail: L(
                        "%1$@ is %2$@, which does not match a known App Store screenshot size.",
                        asset.url.lastPathComponent, asset.size.displayName),
                    locale: asset.locale ?? Self.unassignedLocaleDisplayName,
                    slot: nil,
                    assetIDs: [asset.id]
                ))
        }

        let unassigned = assets.filter { $0.locale == nil }
        if !unassigned.isEmpty {
            issues.append(
                ScreenshotIssue(
                    severity: .warning,
                    title: L("Locale not detected"),
                    detail: L(
                        "%d screenshot(s) are not inside a recognizable locale folder or filename. Put them in a locale folder like en-US or include the locale code in the filename.",
                        unassigned.count),
                    locale: Self.unassignedLocaleDisplayName,
                    slot: nil,
                    assetIDs: unassigned.map(\.id)
                ))
        }

        let duplicateGroups = Dictionary(
            grouping: assets.compactMap { asset -> (String, ScreenshotAsset)? in
                guard let hash = asset.contentHash else { return nil }
                let key = "\(asset.locale ?? "unassigned")|\(asset.deviceSlot?.rawValue ?? "unknown")|\(hash)"
                return (key, asset)
            }, by: \.0)

        for group in duplicateGroups.values {
            let duplicates = group.map(\.1)
            guard duplicates.count > 1 else { continue }
            let first = duplicates[0]
            issues.append(
                ScreenshotIssue(
                    severity: .warning,
                    title: L("Possible duplicate screenshots"),
                    detail: L(
                        "%d screenshots look identical in %@.", duplicates.count,
                        first.deviceSlot?.displayName ?? L("Unknown Size")),
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
            assetIDs.joined(separator: ","),
        ].joined(separator: "|")
    }

    let severity: ScreenshotIssueSeverity
    let title: String
    let detail: String
    let locale: String?
    let slot: ScreenshotDeviceSlot?
    let assetIDs: [String]
}
