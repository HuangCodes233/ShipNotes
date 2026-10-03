import SwiftUI

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
