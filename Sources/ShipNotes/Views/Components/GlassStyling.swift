import SwiftUI

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
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

private struct StandardGlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.buttonStyle(.glass) } else { content.buttonStyle(.bordered) }
    }
}
