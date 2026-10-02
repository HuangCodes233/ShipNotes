import SwiftUI

struct AppIconView: View {
    let app: AppRecord?
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 7

    var body: some View {
        ZStack {
            fallback
            if let iconURL = app?.iconURL {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var fallback: some View {
        let symbol = app?.iconSystemName ?? "app"
        ZStack {
            fallbackColor
            if symbol != "app" {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(initial)
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private var initial: String {
        let trimmed = (app?.name ?? "A").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "A"
    }

    private var fallbackColor: Color {
        let text = app.map { "\($0.id)-\($0.name)" } ?? "ShipNotes"
        let total = text.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 360 }
        return Color(hue: Double(total) / 360.0, saturation: 0.62, brightness: 0.74)
    }
}

struct StatusBadge: View {
    let status: LocaleStatus
    var body: some View {
        let c = color
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(status.displayName).font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(c.opacity(0.15), in: Capsule())
    }
    private var color: Color {
        switch status {
        case .ready: .green; case .needsReview: .orange; case .missing: .gray
        case .overLimit: .red; case .invalid: .red; case .noChange: .secondary; case .failed: .red
        case .syncing, .synced: .blue
        }
    }
}

struct VersionStateBadge: View {
    let state: AppStoreVersionState
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.isEditable ? "pencil.circle.fill" : "lock.circle.fill")
                .foregroundStyle(state.isEditable ? .green : .gray)
            Text(state.displayName)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct CharacterRing: View {
    let count: Int
    let limit: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if count > limit {
            overLimitBadge
        } else {
            ring
                .frame(width: 32, height: 32)
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: progress)
            Text("\(limit - count)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(color)
        }
        .help(L("%1$d characters used of %2$d. %3$d remaining.", count, limit, max(0, limit - count)))
    }

    private var overLimitBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
            Text("+\(overage.formatted(.number.grouping(.automatic)))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 7)
        .frame(height: 26)
        .fixedSize(horizontal: true, vertical: false)
        .background(.red.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(.red.opacity(0.42), lineWidth: 1))
        .help(L("%1$d characters used of %2$d. %3$d over limit.", count, limit, overage))
    }

    private var progress: Double { limit > 0 ? Double(count) / Double(limit) : 0 }
    private var color: Color { count > limit ? .red : progress > 0.92 ? .orange : .green }
    private var overage: Int { max(0, count - limit) }
}

struct ErrorBanner: View {
    let error: AppError
    let onDismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).font(.system(size: 14, weight: .semibold)).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Something went wrong")).font(.callout.weight(.semibold))
                Text(error.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                } else if error.isRetryable {
                    Text(L("You can try again.")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button { onDismiss() } label: {
                Label(L("Dismiss"), systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).padding(6).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(L("Dismiss"))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        // Material surface + semantic text colors instead of white-on-gradient:
        // white on the orange end of a red→orange gradient measured ~2:1 in
        // light mode, far under the 4.5:1 accessibility floor.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.red.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 12).padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Top-of-window banner that visualizes an in-flight task with a live elapsed
/// timer, so the user can tell the app from "stuck" during multi-second work.
/// Shared by AI and screenshot-upload progress (the tint color distinguishes
/// them). Rendered on a material surface with semantic text colors so contrast
/// holds in both light and dark mode.
struct ProgressBanner: View {
    let message: String
    let startedAt: Date
    var tint: Color = .purple

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                    .tint(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(message)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(elapsedString(now: context.date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(.horizontal, 12).padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func elapsedString(now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(startedAt))
        return L("Elapsed: %.1fs", seconds)
    }
}

/// AI progress (parse / translate / optimize) — purple.
struct AIProgressBanner: View {
    let activity: AppState.AIActivity
    var body: some View {
        ProgressBanner(message: activity.message, startedAt: activity.startedAt, tint: .purple)
    }
}

/// Screenshot upload progress — green, to read as "pushing to the Store".
struct ScreenshotUploadBanner: View {
    let activity: AppState.AIActivity
    var body: some View {
        ProgressBanner(message: activity.message, startedAt: activity.startedAt, tint: .green)
    }
}

// MARK: - Glass Styling

extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    func primarySyncButton() -> some View { modifier(ProminentGlassButton()) }
    func secondaryGlassButton() -> some View { modifier(StandardGlassButton()) }
}

private struct ProminentGlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.buttonStyle(.glassProminent) }
        else { content.buttonStyle(.borderedProminent) }
    }
}

private struct StandardGlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.buttonStyle(.glass) }
        else { content.buttonStyle(.bordered) }
    }
}

struct DropZoneOverlayModifier: ViewModifier {
    let isTargeted: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .background(Color.accentColor.opacity(0.1))
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func dropZoneOverlay(isTargeted: Bool) -> some View {
        modifier(DropZoneOverlayModifier(isTargeted: isTargeted))
    }
}

struct SelectAppEmptyState: View {
    var description: String

    var body: some View {
        ContentUnavailableView {
            Label(L("Select an App"), systemImage: "hand.point.up.left")
        } description: {
            Text(description)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VersionPickerRow: View {
    @Environment(AppState.self) private var state
    @Binding var showNewVersionSheet: Bool

    var body: some View {
        @Bindable var state = state
        let versions = state.selectedAppId.flatMap { state.versionsByApp[$0] } ?? []
        return HStack(spacing: 8) {
            Picker(L("Version"), selection: Binding(
                get: { state.selectedVersionId ?? "" },
                set: { if !$0.isEmpty { state.selectVersion($0) } }
            )) {
                ForEach(versions) { version in
                    if let date = version.createdDate {
                        Text("\(version.versionString) (\(date.formatted(date: .numeric, time: .omitted)))").tag(version.id)
                    } else {
                        Text(version.versionString).tag(version.id)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            // Let the picker compress instead of forcing its intrinsic width;
            // the menu will truncate the version label rather than overflow.

            Button {
                state.refreshSelectedAppVersions()
            } label: {
                Label(L("Refresh Versions"), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(L("Refresh Versions"))
            .disabled(state.selectedAppId == nil || state.isLoadingRemote || state.isUsingMockData)

            Button {
                showNewVersionSheet = true
            } label: {
                Label(L("New Version"), systemImage: "plus.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(L("New Version…"))
            .disabled(state.selectedAppId == nil || state.isLoadingRemote)

            if let version = state.selectedVersion {
                VersionStateBadge(state: version.appStoreState)

                // The created-date and "not editable" label are secondary info;
                // they compress (truncation) before the picker/buttons do.
                if let date = version.createdDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .help(L("Created on %@", date.formatted(date: .complete, time: .omitted)))
                    .layoutPriority(-1)
                }

                if !version.canEditMetadata {
                    Label(L("Version not editable"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
            }

            if state.isLoadingRemote {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .lineLimit(1)
    }
}

struct URLPathCapsule: View {
    let url: URL
    let subtitle: String?
    let iconName: String
    let onRefresh: () -> Void
    let onChange: () -> Void

    init(
        url: URL,
        subtitle: String? = nil,
        iconName: String = "folder.fill",
        onRefresh: @escaping () -> Void,
        onChange: @escaping () -> Void
    ) {
        self.url = url
        self.subtitle = subtitle
        self.iconName = iconName
        self.onRefresh = onRefresh
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button {
                onRefresh()
            } label: {
                Label(L("Refresh"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)

            Button {
                onChange()
            } label: {
                Label(L("Change"), systemImage: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: 10)
    }
}

// MARK: - Modern UI Enhancement Components

// Empty states are consistently the system `ContentUnavailableView` across
// every workspace (see SelectAppEmptyState above); the custom illustrated
// EmptyStateView was removed to keep a single visual language.

struct DeviceFrameView<Content: View>: View {
    let isIPad: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            // Bezel background
            RoundedRectangle(cornerRadius: isIPad ? 18 : 26, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: isIPad ? 18 : 26, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 2)
                )

            // Inner display content
            content()
                .clipShape(RoundedRectangle(cornerRadius: isIPad ? 14 : 20, style: .continuous))
                .padding(isIPad ? 8 : 6)

            // Dynamic Island / Speaker cutout simulation for iPhone
            if !isIPad {
                VStack {
                    Capsule()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 48, height: 10)
                        .padding(.top, 10)
                    Spacer()
                }
            }
        }
    }
}

struct KeywordsTagView: View {
    @Binding var keywordsText: String
    @State private var newTagText: String = ""

    private var tags: [String] { KeywordList.tags(in: keywordsText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                // Offsets, not the text, identify tags: a keyword may appear twice.
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.caption.weight(.medium))
                        Button {
                            removeTag(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Remove keyword %@", tag))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                }
            }

            HStack(spacing: 8) {
                TextField(L("Add keyword..."), text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }

                Button(L("Add")) { addTag() }
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .controlSize(.small)
            }
        }
    }

    private func removeTag(at index: Int) {
        keywordsText = KeywordList.removing(at: index, from: keywordsText)
    }

    private func addTag() {
        guard let updated = KeywordList.adding(newTagText, to: keywordsText) else { return }
        keywordsText = updated
        newTagText = ""
    }
}

/// Editing rules for the comma-separated App Store keywords field.
///
/// The 100-character limit counts separators, so tags are joined with a bare
/// comma (the App Store convention). Joining with ", " made removing one tag
/// add a space per remaining tag and could push a tightly packed field over
/// the limit.
enum KeywordList {
    static let separator = ","

    static func tags(in text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Removes only the tag at `index`; a repeated keyword keeps its twin.
    static func removing(at index: Int, from text: String) -> String {
        var current = tags(in: text)
        guard current.indices.contains(index) else { return text }
        current.remove(at: index)
        return current.joined(separator: separator)
    }

    /// Adds one keyword or a pasted comma-separated list, skipping
    /// case-insensitive duplicates. Returns `nil` when the input is empty.
    static func adding(_ input: String, to text: String) -> String? {
        let additions = tags(in: input)
        guard !additions.isEmpty else { return nil }
        var current = tags(in: text)
        for tag in additions where !current.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            current.append(tag)
        }
        return current.joined(separator: separator)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
