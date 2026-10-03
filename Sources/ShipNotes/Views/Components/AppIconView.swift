import SwiftUI

struct AppIconView: View {
    let app: AppRecord?
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 7

    var body: some View {
        ZStack {
            fallback
            if let iconURL = app?.iconURL {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var fallback: some View {
        let symbol = app?.iconSystemName ?? "app"
        ZStack {
            fallbackColor
            if symbol != "app" {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(initial)
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private var initial: String {
        let trimmed = (app?.name ?? "A").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "A"
    }

    private var fallbackColor: Color {
        let text = app.map { "\($0.id)-\($0.name)" } ?? "ShipNotes"
        let total = text.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 360 }
        return Color(hue: Double(total) / 360.0, saturation: 0.62, brightness: 0.74)
    }
}
