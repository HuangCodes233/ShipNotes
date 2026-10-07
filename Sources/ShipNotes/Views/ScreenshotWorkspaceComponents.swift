import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ScreenshotIssueRow: View {
    let issue: ScreenshotIssue

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? Color.red : (issue.severity == .warning ? .orange : .blue))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(.caption.weight(.semibold))
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(issue.severity.displayName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(self.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(color.opacity(0.12), in: Capsule())
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var color: Color {
        switch issue.severity {
        case .error: .red
        case .warning: .orange
        case .info: .secondary
        }
    }
}

struct ScreenshotSlotSection: View {
    let title: String
    let subtitle: String
    let assets: [ScreenshotAsset]
    let focusedAssetID: String?
    let assetFocusID: (String) -> String
    let move: (ScreenshotAsset, ScreenshotMoveDirection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L("%d file(s)", assets.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if assets.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(L("No screenshots in this required slot."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                        ScreenshotAssetTile(
                            asset: asset,
                            focusID: assetFocusID(asset.id),
                            isFocused: focusedAssetID == asset.id,
                            canMoveUp: index > 0,
                            canMoveDown: index < assets.count - 1,
                            moveUp: { move(asset, .up) },
                            moveDown: { move(asset, .down) }
                        )
                    }
                }
            }
        }
        .padding(10)
        .glassSurface(cornerRadius: 8)
    }
}

struct RequirementPill: View {
    let requirement: ScreenshotSlotRequirement

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checklist")
            Text(requirement.displayName)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .help(requirement.requiredCopy)
    }
}

struct SummaryMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: 8)
    }
}

struct SlotCountBadge: View {
    let count: Int
    let isMissingRequirement: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(count)")
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.13), in: Capsule())
    }

    private var icon: String {
        if count > 0 { return "checkmark.circle.fill" }
        return isMissingRequirement ? "exclamationmark.triangle.fill" : "minus.circle"
    }

    private var color: Color {
        if count > 0 { return .green }
        return isMissingRequirement ? .orange : .secondary
    }
}

struct ScreenshotAssetTile: View {
    let asset: ScreenshotAsset
    let focusID: String
    let isFocused: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeviceFrameView(isIPad: asset.deviceSlot?.displayName.contains("iPad") ?? false) {
                LocalImageThumbnail(url: asset.url, contentHash: asset.contentHash)
                    .frame(height: 110)
            }
            .frame(height: 122)

            VStack(alignment: .leading, spacing: 3) {
                Text(asset.url.lastPathComponent)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(asset.size.displayName)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Image(systemName: asset.status == .ready ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    Text(asset.deviceSlot?.displayName ?? L("Unknown Size"))
                        .lineLimit(1)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(asset.status == .ready ? .green : .red)

                HStack(spacing: 6) {
                    Button(action: moveUp) {
                        Label(L("Move Earlier"), systemImage: "arrow.up")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!canMoveUp)
                    .help(L("Move Earlier"))

                    Button(action: moveDown) {
                        Label(L("Move Later"), systemImage: "arrow.down")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!canMoveDown)
                    .help(L("Move Later"))

                    Spacer()
                    Text(asset.size.orientation.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(8)
        .glassSurface(cornerRadius: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .id(focusID)
        .help(asset.relativePath)
    }
}

struct LocalImageThumbnail: View {
    let url: URL
    var contentHash: String? = nil
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.primary.opacity(0.05))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: ScreenshotThumbnailRequest(url: url, contentHash: contentHash)) {
            let maxPixel: CGFloat = 480
            image = nil
            let loaded = await ScreenshotThumbnailCache.shared.thumbnail(
                for: url, maxPixel: maxPixel, contentHash: contentHash)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

struct ScreenshotThumbnailRequest: Hashable, Sendable {
    let url: URL
    let contentHash: String?
}

/// Builds and caches downsampled thumbnails with ImageIO so repeated
/// locale switches do not decode the same full-size screenshots again.
final class ScreenshotThumbnailCache: @unchecked Sendable {
    static let shared = ScreenshotThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private let maxItems = 500

    private init() {
        cache.countLimit = maxItems
    }

    func thumbnail(for url: URL, maxPixel: CGFloat, contentHash: String? = nil) async -> NSImage? {
        let key = cacheKey(for: url, maxPixel: maxPixel, contentHash: contentHash)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image = await Task.detached(priority: .utility) {
            Self.makeThumbnail(for: url, maxPixel: maxPixel)
        }.value

        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    private func cacheKey(for url: URL, maxPixel: CGFloat, contentHash: String?) -> NSString {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return "\(url.path)|\(Int(maxPixel))|\(contentHash ?? "")|\(fileSize)|\(modifiedAt)" as NSString
    }

    private static func makeThumbnail(for url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        #if canImport(AppKit)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        #else
        return nil
        #endif
    }
}
