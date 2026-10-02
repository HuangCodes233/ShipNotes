import SwiftUI

struct BottomCommandBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 12) {
            // Hide the summary on narrow widths so it never forces the bar to
            // wrap or pushes the buttons off-screen.
            ViewThatFits(in: .horizontal) {
                summaryText
                EmptyView()
            }
            Spacer(minLength: 8)
            Button {
                state.performDryRun()
            } label: {
                Label(L("Dry Run"), systemImage: "play.slash")
                    .lineLimit(1)
            }
            .secondaryGlassButton()
            .disabled(!state.canDryRunReleaseNotes)

            // Only reachable mid-sync, where the Sync button is disabled —
            // gives the user a way out of a long or wedged sync.
            if state.isSyncing {
                Button {
                    state.cancelSync()
                } label: {
                    Label(L("Cancel"), systemImage: "xmark.circle")
                        .lineLimit(1)
                }
                .secondaryGlassButton()
                .help(L("Stop the sync in progress"))
            }

            Button {
                state.performSync()
            } label: {
                Label(state.isSyncing ? L("Syncing") : L("Sync All"), systemImage: state.isSyncing ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up")
                    .lineLimit(1)
            }
            .primarySyncButton()
            .disabled(!state.canSyncAllReleaseNotes)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .glassSurface(cornerRadius: 18)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .padding(.top, 6)
    }

    private var summaryText: some View {
        let stats = state.localeNotesStats
        let parts: [String] = [
            L("%d ready", stats.readyCount),
            stats.needsReviewCount > 0 ? L("%d needs review", stats.needsReviewCount) : nil,
            stats.overLimitCount > 0 ? L("%d over limit", stats.overLimitCount) : nil,
            stats.missingCount > 0 ? L("%d missing notes", stats.missingCount) : nil
        ].compactMap { $0 }

        return Text(parts.joined(separator: " · "))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
