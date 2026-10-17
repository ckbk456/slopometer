import Foundation

/// An sRGB color with the WCAG 2 contrast math, so palette choices can be checked in tests.
public struct ThemeColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0x116329` style hex.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    public static let white = ThemeColor(red: 1, green: 1, blue: 1)
    public static let black = ThemeColor(red: 0, green: 0, blue: 0)

    /// WCAG 2 relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio, 1 to 21.
    public func contrast(with other: ThemeColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This color drawn at `opacity` over `background`, as an opacity fill renders.
    public func blended(over background: ThemeColor, opacity: Double) -> ThemeColor {
        ThemeColor(
            red: red * opacity + background.red * (1 - opacity),
            green: green * opacity + background.green * (1 - opacity),
            blue: blue * opacity + background.blue * (1 - opacity))
    }
}

/// The app's colors by role, one set per appearance. Every surface reads these, so custom
/// colors can later replace a theme without touching views. Activity is the measured slop;
/// trend is the moving average and warnings.
public struct SlopTheme: Codable, Equatable, Sendable {
    public struct Appearance: Codable, Equatable, Sendable {
        /// Fills and graphics: tiles, bars, lines, meter ticks, control tint. At least 3:1
        /// against `background`.
        public var activity: ThemeColor
        /// Text and icons drawn on the background in the activity color. At least 4.5:1.
        public var activityText: ThemeColor
        /// The moving average and warning accents; text use needs 4.5:1 as well.
        public var trend: ThemeColor
        /// The typical window background the contrast targets are measured against.
        public var background: ThemeColor

        public init(
            activity: ThemeColor, activityText: ThemeColor, trend: ThemeColor,
            background: ThemeColor
        ) {
            self.activity = activity
            self.activityText = activityText
            self.trend = trend
            self.background = background
        }

        /// Level 1–4 tile fill as rendered over the background; level 0 is not activity.
        public func fill(level: Int) -> ThemeColor {
            activity.blended(over: background, opacity: SlopTheme.opacity(level: level))
        }

        /// Whether a tile's number reads better in white than in black on its fill.
        public func numberIsLight(level: Int) -> Bool {
            guard level > 0 else { return false }
            let fill = fill(level: level)
            return fill.contrast(with: .white) >= fill.contrast(with: .black)
        }
    }

    public var light: Appearance
    public var dark: Appearance

    public init(light: Appearance, dark: Appearance) {
        self.light = light
        self.dark = dark
    }

    public func appearance(isDark: Bool) -> Appearance { isDark ? dark : light }

    /// Opacity of the activity color for levels 1–4. The steps keep neighboring levels
    /// apart and leave every tile a number color with 4.5:1 contrast.
    public static let levelOpacities = [0.35, 0.55, 0.75, 1.0]

    public static func opacity(level: Int) -> Double {
        levelOpacities[min(max(level, 1), levelOpacities.count) - 1]
    }

    /// Darker green in light appearance so text reads on light and translucent
    /// backgrounds; dark appearance keeps the brighter green that already read well.
    public static let standard = SlopTheme(
        light: Appearance(
            activity: ThemeColor(hex: 0x116329), activityText: ThemeColor(hex: 0x116329),
            trend: ThemeColor(hex: 0x8A5C00), background: ThemeColor(hex: 0xF5F5F5)),
        dark: Appearance(
            activity: ThemeColor(hex: 0x2EA043), activityText: ThemeColor(hex: 0x2EA043),
            trend: ThemeColor(hex: 0xD29922), background: ThemeColor(hex: 0x1E1E1E)))
}
