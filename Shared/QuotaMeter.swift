import SlopometerCore
import SwiftUI
import WidgetKit

/// The quota as a row of ticks, one per unit of the target, so progress reads like an
/// instrument rather than a loading bar. Counts past the target extend as an overflow
/// figure instead of being capped. Large targets fall back to a continuous track.
struct QuotaMeter: View {
    let count: Int
    let target: Int
    var height: CGFloat = 10
    @Environment(\.slopColors) private var colors
    @Environment(\.widgetRenderingMode) private var renderingMode

    private static let maxTicks = 20

    private var isFullColor: Bool { renderingMode == .fullColor }

    /// The theme's color for a filled tick: the accent, or its step along the gradient.
    /// Full white when the desktop draws the widget in one color, so filled ticks stay
    /// clearly brighter than the track.
    private func filled(tick index: Int) -> Color {
        isFullColor ? colors.meterFill(tick: index, of: target) : .white
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
                            ? colors.markText : .primary)
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
                    .fill(index < count ? filled(tick: index) : SlopPalette.track)
                    .widgetAccentable(index < count)
                    .frame(width: side)
            }
        }
    }

    private func track(width: CGFloat) -> some View {
        let fraction = min(1, Double(count) / Double(max(target, 1)))
        return ZStack(alignment: .leading) {
            Capsule().fill(SlopPalette.track)
            Capsule().fill(fill(upTo: fraction)).widgetAccentable().frame(width: width * fraction)
        }
    }

    /// The continuous track's filled part. With a gradient meter it walks the gradient from
    /// the start to `fraction`, as the ticks would, sampled so it mixes like the ticks do.
    private func fill(upTo fraction: Double) -> AnyShapeStyle {
        guard isFullColor else { return AnyShapeStyle(Color.white) }
        guard colors.appearance.meter == .gradient else { return AnyShapeStyle(colors.mark) }
        let steps = 8
        let stops = (0...steps).map { step in
            let location = Double(step) / Double(steps)
            return Gradient.Stop(
                color: Color(colors.appearance.color(at: fraction * location)),
                location: location)
        }
        return AnyShapeStyle(
            LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
    }
}
