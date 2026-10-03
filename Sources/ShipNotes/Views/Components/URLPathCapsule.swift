import SwiftUI

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
