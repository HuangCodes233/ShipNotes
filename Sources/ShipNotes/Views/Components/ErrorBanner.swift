import SwiftUI

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
            Button {
                onDismiss()
            } label: {
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
