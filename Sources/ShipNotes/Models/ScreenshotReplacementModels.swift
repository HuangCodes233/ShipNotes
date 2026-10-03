import Foundation

struct RemoteScreenshot: Identifiable, Hashable, Sendable {
    let id: String
    var fileName: String
    var fileSize: Int?
    var imageURL: URL?
    var width: Int?
    var height: Int?
}

struct RemoteScreenshotSet: Identifiable, Hashable, Sendable {
    let id: String
    var localizationId: String
    var displayType: String
    var slot: ScreenshotDeviceSlot?
    var screenshots: [RemoteScreenshot]
}

struct ScreenshotReplacementSlotPlan: Identifiable, Hashable, Sendable {
    var id: String { slot.id }
    var slot: ScreenshotDeviceSlot
    var remoteScreenshots: [RemoteScreenshot]
    var localAssets: [ScreenshotAsset]

    var replacesRemote: Bool { !localAssets.isEmpty }
}

struct ScreenshotReplacementLocalePlan: Identifiable, Hashable, Sendable {
    var id: String { locale }
    var locale: String
    var localizationId: String?
    var slots: [ScreenshotReplacementSlotPlan]

    var replacingSlots: [ScreenshotReplacementSlotPlan] {
        slots.filter(\.replacesRemote)
    }
}

struct ScreenshotReplacementPlan: Identifiable, Hashable, Sendable {
    let id = UUID()
    var locales: [ScreenshotReplacementLocalePlan]
    /// Selection the preview was built for. The upload targets these IDs, not
    /// whatever is selected when a long multi-locale upload reaches a locale.
    var appId: String? = nil
    var versionId: String? = nil

    var localeCount: Int { locales.count }
    var slotCount: Int { locales.reduce(0) { $0 + $1.replacingSlots.count } }
    var remoteDeleteCount: Int {
        locales.reduce(0) { total, locale in
            total + locale.replacingSlots.reduce(0) { $0 + $1.remoteScreenshots.count }
        }
    }
    var localUploadCount: Int {
        locales.reduce(0) { total, locale in
            total + locale.replacingSlots.reduce(0) { $0 + $1.localAssets.count }
        }
    }
}

struct ScreenshotPreviewControlsState: Equatable, Sendable {
    let selectedDisabledReason: String?
    let allDisabledReason: String?
}
