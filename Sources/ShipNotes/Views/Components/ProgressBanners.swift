import SwiftUI

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
