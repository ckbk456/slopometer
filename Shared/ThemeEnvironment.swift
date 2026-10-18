import SlopometerCore
import SwiftUI

extension EnvironmentValues {
    /// The person's theme for both appearances. Set once per window, panel, and widget with
    /// `slopTheme(_:)`; views read the resolved `slopColors`.
    @Entry var slopTheme = SlopTheme.standard
    /// `slopTheme` resolved for the current color scheme.
    @Entry var slopColors = SlopColors(appearance: SlopTheme.standard.light)
    /// Comfortable unless the app window or menu bar panel sets compact.
    @Entry var density = Density.comfortable
}

extension Density {
    /// Picks the comfortable or compact value of a spacing or padding.
    func pick(_ comfortable: CGFloat, _ compact: CGFloat) -> CGFloat {
        self == .compact ? compact : comfortable
    }
}

extension View {
    /// Applies `theme` to this view and everything in it, following its color scheme.
    func slopTheme(_ theme: SlopTheme) -> some View {
        modifier(SlopThemeModifier(theme: theme))
    }
}

private struct SlopThemeModifier: ViewModifier {
    let theme: SlopTheme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = SlopColors(appearance: theme.appearance(isDark: colorScheme == .dark))
        content
            .environment(\.slopTheme, theme)
            .environment(\.slopColors, colors)
            .tint(colors.mark)
    }
}

/// One appearance's colors as SwiftUI colors, resolved without AppKit so widgets render
/// them as drawn.
struct SlopColors {
    let appearance: SlopTheme.Appearance

    /// Control tint, badges, and graphics in the accent color.
    var mark: Color { Color(appearance.accent) }
    /// Text and icons in the accent color.
    var markText: Color { Color(appearance.accentText) }
    /// The moving average line.
    var average: Color { Color(appearance.trend) }
    /// Incomplete coverage and other warnings.
    var warning: Color { Color(appearance.warning) }
    /// The gradient, low to high, for previews and swatches.
    var gradient: Gradient { Gradient(colors: appearance.gradient.map(Color.init)) }

    /// The neutral fill of a day with no activity.
    static let empty = Color.secondary.opacity(0.12)

    func fill(level: Int) -> Color {
        level == 0 ? Self.empty : Color(appearance.fill(level: level))
    }

    /// A day's fill, following the theme's levels or smooth mapping.
    func fill(count: Int, busiest: Int) -> Color {
        appearance.fill(count: count, busiest: busiest).map(Color.init) ?? Self.empty
    }

    /// White or black, whichever reads better on the day's fill; primary on empty days.
    func number(count: Int, busiest: Int) -> Color {
        guard let fill = appearance.fill(count: count, busiest: busiest) else { return .primary }
        return fill.prefersLightText ? .white : .black
    }

    /// White or black, whichever reads better on the level's fill; primary on level 0.
    func number(level: Int) -> Color {
        guard level > 0 else { return .primary }
        return appearance.numberIsLight(level: level) ? .white : .black
    }

    func meterFill(tick index: Int, of target: Int) -> Color {
        Color(appearance.meterFill(tick: index, of: target))
    }
}
