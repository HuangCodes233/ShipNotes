import Foundation

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
                ScreenshotPixelSize(width: 2868, height: 1320),
            ]
        case .iPhone65:
            [
                ScreenshotPixelSize(width: 1242, height: 2688),
                ScreenshotPixelSize(width: 2688, height: 1242),
                ScreenshotPixelSize(width: 1284, height: 2778),
                ScreenshotPixelSize(width: 2778, height: 1284),
            ]
        case .iPad13:
            [
                ScreenshotPixelSize(width: 2064, height: 2752),
                ScreenshotPixelSize(width: 2752, height: 2064),
                ScreenshotPixelSize(width: 2048, height: 2732),
                ScreenshotPixelSize(width: 2732, height: 2048),
            ]
        case .mac:
            [
                ScreenshotPixelSize(width: 1280, height: 800),
                ScreenshotPixelSize(width: 1440, height: 900),
                ScreenshotPixelSize(width: 2560, height: 1600),
                ScreenshotPixelSize(width: 2880, height: 1800),
            ]
        case .appleTV:
            [
                ScreenshotPixelSize(width: 1920, height: 1080),
                ScreenshotPixelSize(width: 3840, height: 2160),
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
                ScreenshotPixelSize(width: 312, height: 390),
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
