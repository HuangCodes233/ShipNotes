import SwiftUI

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
        case .ready: .green;
        case .needsReview: .orange;
        case .missing: .gray
        case .overLimit: .red;
        case .invalid: .red;
        case .noChange: .secondary;
        case .failed: .red
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
