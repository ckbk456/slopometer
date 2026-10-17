import SwiftUI
import WidgetKit

/// The quota as a row of ticks, one per unit of the target, so progress reads like an
/// instrument rather than a loading bar. Counts past the target extend as an overflow
/// figure instead of being capped. Large targets fall back to a continuous track.
struct QuotaMeter: View {
    let count: Int
    let target: Int
    var height: CGFloat = 10
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    private static let maxTicks = 20

    /// Full white when the desktop draws the widget in one color, so filled ticks stay
    /// clearly brighter than the track.
    private var filled: Color {
        renderingMode == .fullColor ? SlopPalette.colors(colorScheme).mark : .white
    }

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
                    .foregroundStyle(
                        renderingMode == .fullColor
                            ? SlopPalette.colors(colorScheme).markText : .primary)
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
                    .fill(index < count ? filled : SlopPalette.track)
                    .widgetAccentable(index < count)
                    .frame(width: side)
            }
        }
    }

    private func track(width: CGFloat) -> some View {
        let fraction = min(1, Double(count) / Double(max(target, 1)))
        return ZStack(alignment: .leading) {
            Capsule().fill(SlopPalette.track)
            Capsule().fill(filled).widgetAccentable().frame(width: width * fraction)
        }
    }
}
