import SwiftUI

struct ScreenshotReplacementPreviewSheet: View {
    @Environment(AppState.self) private var state
    let plan: ScreenshotReplacementPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Screenshot Replacement Preview"))
                        .font(.title3.bold())
                    Text(L(
                        "Will replace %1$d screenshot set(s). For each set, delete old screenshots and confirm it is empty before uploading new ones (%2$d remote, %3$d local). If upload fails, the set may be empty or incomplete.",
                        plan.slotCount,
                        plan.remoteDeleteCount,
                        plan.localUploadCount
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.locales) { localePlan in
                        ScreenshotReplacementLocaleSection(localePlan: localePlan)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 280, maxHeight: 560)

            HStack {
                Spacer()
                Button(L("Cancel")) {
                    state.dismissScreenshotReplacementPreview()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    state.confirmScreenshotReplacementPreview()
                } label: {
                    Label(L("Replace Screenshots"), systemImage: "icloud.and.arrow.up")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 460)
    }
}

struct ScreenshotReplacementLocaleSection: View {
    let localePlan: ScreenshotReplacementLocalePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(localePlan.locale)
                    .font(.headline)
                Text(L("%d screenshot set(s)", localePlan.replacingSlots.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                Spacer()
            }

            ForEach(localePlan.replacingSlots) { slotPlan in
                ScreenshotReplacementSlotRow(slotPlan: slotPlan)
            }
        }
        .padding(12)
        .glassSurface(cornerRadius: 10)
    }
}

struct ScreenshotReplacementSlotRow: View {
    let slotPlan: ScreenshotReplacementSlotPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(slotPlan.slot.displayName)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(L("%1$d remote to %2$d local", slotPlan.remoteScreenshots.count, slotPlan.localAssets.count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ScreenshotReplacementPreviewPane(
                    title: L("Current App Store Connect screenshots"),
                    systemImage: "icloud"
                ) {
                    ScreenshotReplacementTileStrip {
                        if slotPlan.remoteScreenshots.isEmpty {
                            EmptyScreenshotTile(title: L("No remote screenshots"), systemImage: "photo")
                        } else {
                            ForEach(slotPlan.remoteScreenshots) { screenshot in
                                RemoteScreenshotTile(screenshot: screenshot)
                            }
                        }
                    }
                }

                Image(systemName: "arrow.down")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                ScreenshotReplacementPreviewPane(
                    title: L("Local screenshots to upload"),
                    systemImage: "folder"
                ) {
                    ScreenshotReplacementTileStrip {
                        if slotPlan.localAssets.isEmpty {
                            EmptyScreenshotTile(title: L("No local screenshots"), systemImage: "photo")
                        } else {
                            ForEach(slotPlan.localAssets) { asset in
                                LocalScreenshotReplacementTile(asset: asset)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ScreenshotReplacementPreviewPane<Content: View>: View {
    let title: String
    let systemImage: String
    let content: () -> Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScreenshotReplacementTileStrip<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 104, maximum: 104), spacing: 8, alignment: .top)
        ], alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RemoteScreenshotTile: View {
    let screenshot: RemoteScreenshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                if let imageURL = screenshot.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(4)
                        case .failure:
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundStyle(.secondary)
                        case .empty:
                            ProgressView()
                                .controlSize(.small)
                        @unknown default:
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 118)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
            )

            Text(screenshot.fileName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 104, alignment: .leading)
            Text(detailText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
        }
    }

    private var detailText: String {
        let size = screenshot.width.flatMap { width in
            screenshot.height.map { height in "\(width) x \(height)" }
        }
        let fileSize = screenshot.fileSize.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        }
        return [size, fileSize].compactMap { $0 }.joined(separator: " · ")
    }
}

struct LocalScreenshotReplacementTile: View {
    let asset: ScreenshotAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalImageThumbnail(url: asset.url)
                .frame(width: 104, height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                )
            Text(asset.url.lastPathComponent)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 104, alignment: .leading)
            Text(asset.size.displayName)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
        }
    }
}

struct EmptyScreenshotTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 140, height: 118)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
        )
    }
}
