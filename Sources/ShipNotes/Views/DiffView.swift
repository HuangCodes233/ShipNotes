import SwiftUI

struct DiffView: View {
    let note: LocaleNote
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("shipnotes.isDiffCollapsed") private var isCollapsed = false

    // Cache the diff so we don't run an O(N×M) LCS on every body evaluation.
    // Without this, the column animation re-computes the full diff ~60×/sec
    // and the sidebar toggle feels janky.
    @State private var diffLines: [DiffLine] = []
    @State private var lastKey: String = ""
    @State private var isSideBySide = false

    private var addedCount: Int { diffLines.filter { $0.kind == .added }.count }
    private var removedCount: Int { diffLines.filter { $0.kind == .removed }.count }
    private var hasChanges: Bool { note.localText != (note.remoteText ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L("Diff vs App Store Connect")).font(.headline)

                // Diff Statistics Header Pill
                if hasChanges && !diffLines.isEmpty {
                    HStack(spacing: 6) {
                        Text("+\(addedCount)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                        Text("-\(removedCount)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                }

                Spacer()

                if hasChanges {
                    Button {
                        isSideBySide.toggle()
                    } label: {
                        // The label names the view you'll switch TO, not the
                        // one you're looking at.
                        Label(
                            isSideBySide ? L("Unified") : L("Side-by-Side"),
                            systemImage: isSideBySide ? "line.3.horizontal" : "rectangle.split.2x1"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Toggle Side-by-Side or Unified diff view"))

                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCollapsed ? L("Expand differences") : L("Collapse differences"))
                    .help(isCollapsed ? L("Expand differences") : L("Collapse differences"))
                }
            }

            if !hasChanges {
                Label(L("No text changes. Edit below to prepare an update."), systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if !isCollapsed {
                if isSideBySide {
                    sideBySide
                } else {
                    unified
                }
            }
        }
        .clipped()
        .task(id: textKey) { recomputeDiff() }
    }

    private var unified: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Identity by offset (not DiffLine.id, a fresh UUID on every
                // recompute) so rows are reused instead of rebuilt per keystroke.
                ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                    DiffRow(line: line)
                }
            }
            .padding(8)
        }
        .frame(minHeight: 140, maxHeight: 280)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Side-by-side

    /// One removed line paired with the added line that replaces it. Both
    /// columns live in a single scroll container and stay row-aligned, which
    /// is what makes the two sides scroll in lockstep — the old layout was two
    /// independent ScrollViews showing unhighlighted text, which couldn't
    /// actually be compared.
    private var sideBySideRows: [(left: DiffLine?, right: DiffLine?)] {
        var rows: [(DiffLine?, DiffLine?)] = []
        var pendingRemoved: [DiffLine] = []
        func drainPendingRemoved() {
            while !pendingRemoved.isEmpty {
                rows.append((pendingRemoved.removeFirst(), nil))
            }
        }
        for line in diffLines {
            switch line.kind {
            case .removed:
                pendingRemoved.append(line)
            case .added:
                if !pendingRemoved.isEmpty {
                    rows.append((pendingRemoved.removeFirst(), line))
                } else {
                    rows.append((nil, line))
                }
            case .unchanged:
                drainPendingRemoved()
                rows.append((line, line))
            }
        }
        drainPendingRemoved()
        return rows
    }

    private var sideBySide: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text(L("Remote (App Store Connect)"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color(nsColor: .separatorColor)
                    .frame(width: 0.5)
                Text(L("Local Workspace"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sideBySideRows.enumerated()), id: \.offset) { _, row in
                        sideBySideRow(row)
                    }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
        }
        .frame(minHeight: 140, maxHeight: 280)
    }

    private func sideBySideRow(_ row: (left: DiffLine?, right: DiffLine?)) -> some View {
        HStack(spacing: 0) {
            sideBySideCell(row.left, highlight: .removed)
            Color(nsColor: .separatorColor)
                .frame(width: 0.5)
            sideBySideCell(row.right, highlight: .added)
        }
    }

    @ViewBuilder
    private func sideBySideCell(_ line: DiffLine?, highlight: DiffLine.Kind) -> some View {
        let isHighlighted = line?.kind == highlight
        Text(line?.text ?? "")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(isHighlighted ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background {
                // Same tint family as the unified DiffRow highlights.
                if isHighlighted {
                    Rectangle()
                        .fill(highlight == .added ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                }
            }
            .opacity(line == nil ? 0 : 1)
            .accessibilityHidden(line == nil)
    }

    private var textKey: String {
        "\(note.locale)\u{1F}\(note.remoteText ?? "")\u{1F}\(note.localText)"
    }

    private func recomputeDiff() {
        guard textKey != lastKey else { return }
        lastKey = textKey
        diffLines = DiffEngine().diff(old: note.remoteText ?? "", new: note.localText)
    }
}

struct DiffRow: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(prefix)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)
            Text(line.text)
                .font(.system(.caption, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(backgroundColor)
    }

    private var prefix: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .added: return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        case .unchanged: return Color.clear
        }
    }
}
