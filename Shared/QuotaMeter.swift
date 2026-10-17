import SwiftUI

/// The quota as a row of ticks, one per unit of the target, so progress reads like an
/// instrument rather than a loading bar. Counts past the target extend as an overflow
/// figure instead of being capped. Large targets fall back to a continuous track.
struct QuotaMeter: View {
    let count: Int
    let target: Int
    var height: CGFloat = 10

    private static let maxTicks = 20

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                if target <= Self.maxTicks {
                    ticks(width: geometry.size.width)
                } else {
                    track(width: geometry.size.width)
                }
            }
            .frame(height: height)
            if count > target {
                Text("+\(count - target)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SlopPalette.mark)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(count) of \(target)")
    }

    private func ticks(width: CGFloat) -> some View {
        let gap: CGFloat = target > 10 ? 3 : 4
        let side = max(2, (width - gap * CGFloat(target - 1)) / CGFloat(max(target, 1)))
        return HStack(spacing: gap) {
            ForEach(0..<target, id: \.self) { index in
                Capsule()
                    .fill(index < count ? SlopPalette.mark : SlopPalette.track)
                    .frame(width: side)
            }
        }
    }

    private func track(width: CGFloat) -> some View {
        let fraction = min(1, Double(count) / Double(max(target, 1)))
        return ZStack(alignment: .leading) {
            Capsule().fill(SlopPalette.track)
            Capsule().fill(SlopPalette.mark).frame(width: width * fraction)
        }
    }
}
