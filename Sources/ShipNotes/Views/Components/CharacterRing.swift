import SwiftUI

struct CharacterRing: View {
    let count: Int
    let limit: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if count > limit {
            overLimitBadge
        } else {
            ring
                .frame(width: 32, height: 32)
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: progress)
            Text("\(limit - count)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(color)
        }
        .help(L("%1$d characters used of %2$d. %3$d remaining.", count, limit, max(0, limit - count)))
    }

    private var overLimitBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
            Text("+\(overage.formatted(.number.grouping(.automatic)))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 7)
        .frame(height: 26)
        .fixedSize(horizontal: true, vertical: false)
        .background(.red.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(.red.opacity(0.42), lineWidth: 1))
        .help(L("%1$d characters used of %2$d. %3$d over limit.", count, limit, overage))
    }

    private var progress: Double { limit > 0 ? Double(count) / Double(limit) : 0 }
    private var color: Color { count > limit ? .red : progress > 0.92 ? .orange : .green }
    private var overage: Int { max(0, count - limit) }
}
