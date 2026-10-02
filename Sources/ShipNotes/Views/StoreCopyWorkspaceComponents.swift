import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// Field editors and compare panel extracted from StoreCopyWorkspaceView.

/// Draggable split divider shared by the Store Copy and Release Notes splits;
/// `resizeDescription` names the pane being resized for accessibility/help.
struct PaneSplitDivider: View {
    var resizeDescription: String

    @State private var isHovered = false

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(isHovered ? Color.accentColor : Color(nsColor: .separatorColor))
                .frame(width: isHovered ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovered = true
                NSCursor.resizeLeftRight.set()
            case .ended:
                isHovered = false
                NSCursor.arrow.set()
            }
        }
        .accessibilityLabel(resizeDescription)
        .help(resizeDescription)
    }
}

struct StoreCopyTextBlock: View {
    let field: StoreCopyField
    @Binding var text: String
    let issues: [StoreCopyIssue]
    var minHeight: CGFloat
    let remoteText: String?
    let isComparing: Bool
    let canSyncField: Bool
    let onToggleCompare: () -> Void
    let onSyncField: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            TextEditor(text: $text)
                .font(.system(.body, design: .default))
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                // Leave room at the bottom for the character ring so the last
                // line of text isn't hidden behind it. Without this inset the
                // editor's scrollable content is taller than the visible area
                // by a few pixels, so macOS shows a scrollbar even when the
                // text looks like it fits.
                .contentMargins(.bottom, 28, for: .scrollContent)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.8)
                )
                .overlay(alignment: .bottomTrailing) {
                    // Always mounted: CharacterRing renders the red "+N over"
                    // badge itself when the limit is exceeded, so the counter
                    // never vanishes at the exact moment it matters.
                    if let limit = field.limit {
                        CharacterRing(count: text.count, limit: limit)
                            .padding(10)
                    }
                }
            issueList
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(field.title)
                .font(.headline)
            if field.isVersionLocalizationField {
                StoreCopyFieldChangeBadge(localText: text, remoteText: remoteText)
            } else {
                Text(L("Local draft; update this field in App Store Connect."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if field.isVersionLocalizationField && remoteText != nil {
                Button {
                    onToggleCompare()
                } label: {
                    Label(isComparing ? L("Hide Compare") : L("Compare"), systemImage: "arrow.left.arrow.right")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .help(L("Compare this field with App Store Connect."))
            }
            Button {
                onSyncField()
            } label: {
                Label(L("Sync Field"), systemImage: "icloud.and.arrow.up")
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .disabled(!canSyncField)
            .help(L("Upload only this field to App Store Connect."))
            // The overlay ring already switches to the "+N over" badge when
            // past the limit; the header keeps a plain counter and just turns
            // red, instead of swapping to a second ring widget.
            if let limit = field.limit {
                Text(L("%1$d / %2$d", text.count, limit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(text.count > limit ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    private var issueList: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(issues) { issue in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? Color.red : .orange)
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var borderColor: Color {
        if issues.contains(where: { $0.severity == .error }) { return .red.opacity(0.65) }
        if issues.contains(where: { $0.severity == .warning }) { return .orange.opacity(0.65) }
        return .secondary.opacity(0.35)
    }


}

struct StoreCopyURLField: View {
    let field: StoreCopyField
    @Binding var text: String
    let issues: [StoreCopyIssue]
    let remoteText: String?
    let isComparing: Bool
    let canSyncField: Bool
    let onToggleCompare: () -> Void
    let onSyncField: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(field.title)
                    .font(.headline)
                if field.isVersionLocalizationField {
                    StoreCopyFieldChangeBadge(localText: text, remoteText: remoteText)
                } else {
                    Text(L("Local draft; update this field in App Store Connect."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if field.isVersionLocalizationField && remoteText != nil {
                    Button {
                        onToggleCompare()
                    } label: {
                        Label(isComparing ? L("Hide Compare") : L("Compare"), systemImage: "arrow.left.arrow.right")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .help(L("Compare this field with App Store Connect."))
                }
                Button {
                    onSyncField()
                } label: {
                    Label(L("Sync Field"), systemImage: "icloud.and.arrow.up")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .disabled(!canSyncField)
                .help(L("Upload only this field to App Store Connect."))
            }
            HStack(spacing: 8) {
                TextField("https://", text: $text)
                    .textFieldStyle(.roundedBorder)
                ForEach(issues) { issue in
                    Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.severity == .error ? Color.red : .orange)
                        .help(issue.message)
                }
            }
            if !issues.isEmpty {
                ForEach(issues) { issue in
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                }
            }
        }
    }


}

struct StoreCopyFieldChangeBadge: View {
    let localText: String
    let remoteText: String?

    var body: some View {
        if let kind {
            HStack(spacing: 4) {
                Circle()
                    .fill(kind.color)
                    .frame(width: 6, height: 6)
                Text(kind.title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(kind.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(kind.color.opacity(0.12), in: Capsule())
        }
    }

    private var kind: Kind? {
        guard let remoteText else { return nil }
        if localText == remoteText { return .unchanged }
        if remoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .new
        }
        return .changed
    }

    private enum Kind {
        case unchanged
        case changed
        case new

        var title: String {
            switch self {
            case .unchanged: L("No Change")
            case .changed: L("Changed")
            case .new: L("New")
            }
        }

        var color: Color {
            switch self {
            case .unchanged: .secondary
            case .changed: .orange
            case .new: .green
            }
        }
    }
}

struct StoreCopyComparePanel: View {
    let field: StoreCopyField
    let localText: String
    let remoteText: String?

    @State private var diffLines: [DiffLine] = []
    @State private var lastKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(L("Compare with App Store Connect"), systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold))
                Spacer()
                legend(title: L("App Store Connect"), color: .red, symbol: "−")
                legend(title: L("Local Draft"), color: .green, symbol: "+")
            }

            if diffLines.isEmpty {
                Text(L("No differences."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Identity by offset (not DiffLine.id, a fresh UUID on
                        // every recompute) so rows are reused while typing.
                        ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                            DiffRow(line: line)
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: field.isURLField ? 64 : 96, maxHeight: field == .description ? 220 : 140)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: textKey) { recomputeDiff() }
    }

    private var textKey: String {
        "\(remoteText ?? "")\u{1F}\(localText)"
    }

    private func recomputeDiff() {
        guard textKey != lastKey else { return }
        lastKey = textKey
        diffLines = DiffEngine().diff(old: remoteText ?? "", new: localText)
    }

    private func legend(title: String, color: Color, symbol: String) -> some View {
        HStack(spacing: 4) {
            Text(symbol)
                .font(.caption.monospaced().weight(.bold))
            Text(title)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
    }
}
