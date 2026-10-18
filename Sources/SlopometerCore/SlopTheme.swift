import Foundation

/// An sRGB color with the WCAG 2 contrast math, so palette choices can be checked in tests.
public struct ThemeColor: Codable, Equatable, Hashable, Sendable {
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

    /// `#116329` or `116329`; nil for anything else.
    public init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// `#116329`.
    public var hexString: String {
        func byte(_ c: Double) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    public static let white = ThemeColor(red: 1, green: 1, blue: 1)
    public static let black = ThemeColor(red: 0, green: 0, blue: 0)

    /// WCAG 2 relative luminance.
    public var luminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    /// WCAG 2 contrast ratio, 1 to 21.
    public func contrast(with other: ThemeColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Whether white reads better than black on this color.
    public var prefersLightText: Bool { contrast(with: .white) >= contrast(with: .black) }

    // MARK: OKLab, so gradients mix without muddy or dark midpoints

    /// Perceptual lightness, 0 (black) to 1 (white).
    public var lightness: Double { oklab.l }

    /// The color `t` of the way to `other`, mixed in OKLab.
    public func mixed(with other: ThemeColor, by t: Double) -> ThemeColor {
        if t <= 0 { return self }
        if t >= 1 { return other }
        let (a, b) = (oklab, other.oklab)
        return ThemeColor(
            oklab: (a.l + (b.l - a.l) * t, a.a + (b.a - a.a) * t, a.b + (b.b - a.b) * t))
    }

    /// The nearest color with at least `ratio` contrast on `background`, moving only the
    /// lightness toward black or white, whichever the background is farther from.
    public func readable(on background: ThemeColor, ratio: Double = 4.5) -> ThemeColor {
        guard contrast(with: background) < ratio else { return self }
        let target: ThemeColor = background.prefersLightText ? .white : .black
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if mixed(with: target, by: middle).contrast(with: background) >= ratio {
                high = middle
            } else {
                low = middle
            }
        }
        return mixed(with: target, by: high)
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ c: Double) -> Double {
        let c = min(max(c, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private var oklab: (l: Double, a: Double, b: Double) {
        let (r, g, b) = (Self.linear(red), Self.linear(green), Self.linear(blue))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    private init(oklab: (l: Double, a: Double, b: Double)) {
        let l = pow(oklab.l + 0.3963377774 * oklab.a + 0.2158037573 * oklab.b, 3)
        let m = pow(oklab.l - 0.1055613458 * oklab.a - 0.0638541728 * oklab.b, 3)
        let s = pow(oklab.l - 0.0894841775 * oklab.a - 1.2914855480 * oklab.b, 3)
        self.init(
            red: Self.gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            green: Self.gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            blue: Self.gamma(-0.0041960863 * l - 0.7034186168 * m + 1.7076147010 * s))
    }
}

/// How a day's count picks its color from the activity gradient.
public enum ColorMapping: String, Codable, CaseIterable, Identifiable, Sendable {
    /// GitHub-style levels 1–4, sampled evenly from the gradient.
    case levels
    /// Every count gets its own position, from the first color (1) to the last (busiest day).
    case continuous

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .levels: "4 levels"
        case .continuous: "Smooth"
        }
    }
}

/// What fills the quota meter's ticks.
public enum MeterColoring: String, Codable, CaseIterable, Identifiable, Sendable {
    case accent
    /// Ticks walk the activity gradient from the first tick to the target.
    case gradient

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accent: "Accent"
        case .gradient: "Gradient"
        }
    }
}

/// The colors a person chooses: a theme is a preset or their own edit of one. Text and
/// window backgrounds stay with the system on purpose, so a choice cannot make labels
/// unreadable; `resolved()` derives readable text colors from these.
/// The palette set aside while light and dark share one, saved so turning sharing off
/// restores it even after Settings closes or the app restarts.
public struct SetAsidePalette: Codable, Equatable, Sendable {
    public var palette: ColorTheme.Palette
    /// Which appearance it came from.
    public var isDark: Bool

    public init(palette: ColorTheme.Palette, isDark: Bool) {
        self.palette = palette
        self.isDark = isDark
    }
}

public struct ColorTheme: Codable, Equatable, Sendable {
    /// One appearance's choices.
    public struct Palette: Codable, Equatable, Sendable {
        /// Low to high activity, evenly spaced; 2 to `ColorTheme.maxColors` colors.
        public var gradient: [ThemeColor]
        /// Control tint, badges, and highlighted numbers; nil follows the gradient's end.
        public var accent: ThemeColor?
        /// The moving average line.
        public var trend: ThemeColor

        public init(gradient: [ThemeColor], accent: ThemeColor? = nil, trend: ThemeColor) {
            self.gradient = gradient
            self.accent = accent
            self.trend = trend
        }
    }

    public static let minColors = 2
    public static let maxColors = 8

    /// The preset this theme matches; nil once edited.
    public var presetID: String?
    public var light: Palette
    /// Nil uses the light colors in dark appearance too.
    public var dark: Palette?
    public var mapping: ColorMapping
    public var meter: MeterColoring

    public init(
        presetID: String? = nil, light: Palette, dark: Palette? = nil,
        mapping: ColorMapping = .levels, meter: MeterColoring = .accent
    ) {
        self.presetID = presetID
        self.light = light
        self.dark = dark
        self.mapping = mapping
        self.meter = meter
    }

    public func palette(isDark: Bool) -> Palette { isDark ? (dark ?? light) : light }

    /// The default theme: Slop Electric.
    public static var standard: ColorTheme { ThemePreset.electric.theme }

    /// Colors by role for both appearances, with text made readable on each background.
    public func resolved() -> SlopTheme {
        SlopTheme(
            light: SlopTheme.Appearance(
                palette: light, background: SlopTheme.lightBackground, mapping: mapping,
                meter: meter),
            dark: SlopTheme.Appearance(
                palette: palette(isDark: true), background: SlopTheme.darkBackground,
                mapping: mapping, meter: meter))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.standard
        presetID = try container.decodeIfPresent(String.self, forKey: .presetID)
        light = try container.decodeIfPresent(Palette.self, forKey: .light) ?? defaults.light
        dark = try container.decodeIfPresent(Palette.self, forKey: .dark)
        mapping =
            try container.decodeIfPresent(ColorMapping.self, forKey: .mapping) ?? defaults.mapping
        meter = try container.decodeIfPresent(MeterColoring.self, forKey: .meter) ?? defaults.meter
    }
}

/// The app's colors by role, resolved per appearance from a `ColorTheme`. Every surface
/// reads these. Activity is the measured slop; trend is the moving average.
public struct SlopTheme: Equatable, Sendable {
    public struct Appearance: Equatable, Sendable {
        /// Low to high activity; at least two colors.
        public var gradient: [ThemeColor]
        /// Control tint, meter ticks, and other graphics.
        public var accent: ThemeColor
        /// Text and icons in the accent color, at least 4.5:1 on `background`.
        public var accentText: ThemeColor
        /// The moving average line, at least 3:1 on `background`.
        public var trend: ThemeColor
        /// Warnings: incomplete coverage, modified builds. Not themable.
        public var warning: ThemeColor
        /// The typical window background the contrast targets are measured against.
        public var background: ThemeColor
        public var mapping: ColorMapping
        public var meter: MeterColoring

        public init(
            palette: ColorTheme.Palette, background: ThemeColor, mapping: ColorMapping,
            meter: MeterColoring
        ) {
            let gradient =
                palette.gradient.count >= ColorTheme.minColors
                ? Array(palette.gradient.prefix(ColorTheme.maxColors))
                : [palette.gradient.first ?? background, palette.gradient.first ?? .black]
            let accent = palette.accent ?? Self.strongest(gradient, on: background)
            self.gradient = gradient
            self.accent = accent
            accentText = accent.readable(on: background)
            trend = palette.trend.readable(on: background, ratio: 3)
            let isDark = background.luminance < 0.2
            warning = ThemeColor(hex: isDark ? 0xD29922 : 0x8A5C00)
            self.background = background
            self.mapping = mapping
            self.meter = meter
        }

        /// The gradient's color at `t` (0 is the first color, 1 the last).
        public func color(at t: Double) -> ThemeColor {
            let t = min(max(t, 0), 1) * Double(gradient.count - 1)
            let index = min(Int(t), gradient.count - 2)
            return gradient[index].mixed(with: gradient[index + 1], by: t - Double(index))
        }

        /// Level 1–4 fill; level 0 is not activity and has no theme color.
        public func fill(level: Int) -> ThemeColor {
            color(at: Double(min(max(level, 1), 4) - 1) / 3)
        }

        /// A day's fill for `count` when the busiest visible day had `busiest`; nil for zero,
        /// which views draw as the neutral empty tile.
        public func fill(count: Int, busiest: Int) -> ThemeColor? {
            guard count > 0, busiest > 0 else { return nil }
            switch mapping {
            case .levels:
                return fill(level: SlopTheme.level(count, max: busiest))
            case .continuous:
                guard busiest > 1 else { return color(at: 1) }
                return color(at: Double(min(count, busiest) - 1) / Double(busiest - 1))
            }
        }

        /// The quota meter's color for tick `index` of `target`.
        public func meterFill(tick index: Int, of target: Int) -> ThemeColor {
            switch meter {
            case .accent: accent
            case .gradient: color(at: target > 1 ? Double(index) / Double(target - 1) : 1)
            }
        }

        /// Whether a tile's number reads better in white than in black on its fill.
        public func numberIsLight(level: Int) -> Bool {
            guard level > 0 else { return false }
            return fill(level: level).prefersLightText
        }

        /// The gradient color with the most contrast on the background: the accent default.
        static func strongest(_ colors: [ThemeColor], on background: ThemeColor) -> ThemeColor {
            colors.max { $0.contrast(with: background) < $1.contrast(with: background) }
                ?? .black
        }
    }

    public var light: Appearance
    public var dark: Appearance

    public init(light: Appearance, dark: Appearance) {
        self.light = light
        self.dark = dark
    }

    public func appearance(isDark: Bool) -> Appearance { isDark ? dark : light }

    public static let lightBackground = ThemeColor(hex: 0xF5F5F5)
    public static let darkBackground = ThemeColor(hex: 0x1E1E1E)

    /// GitHub-style levels 0–4, scaled to the busiest visible day.
    public static func level(_ count: Int, max: Int) -> Int {
        guard count > 0, max > 0 else { return 0 }
        return Swift.min(4, Swift.max(1, Int((Double(count) / Double(max) * 4).rounded(.up))))
    }

    public static var standard: SlopTheme { ColorTheme.standard.resolved() }
}
