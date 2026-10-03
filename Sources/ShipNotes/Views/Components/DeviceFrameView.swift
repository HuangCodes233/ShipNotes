import SwiftUI

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
