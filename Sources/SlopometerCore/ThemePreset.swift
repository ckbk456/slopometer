import Foundation

/// A named starting point for `ColorTheme`. Presets define both appearances; light
/// gradients run light to dark and dark gradients dark to bright, like GitHub's calendar.
public struct ThemePreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// Distinguishable with the common color-vision deficiencies.
    public let isColorblindSafe: Bool
    public let theme: ColorTheme

    init(
        id: String, name: String, isColorblindSafe: Bool = false, light: [UInt32],
        dark: [UInt32]? = nil, trend: (light: UInt32, dark: UInt32) = (0x8A5C00, 0xD29922),
        mapping: ColorMapping = .levels, meter: MeterColoring = .accent
    ) {
        self.id = id
        self.name = name
        self.isColorblindSafe = isColorblindSafe
        let lightPalette = ColorTheme.Palette(
            gradient: light.map(ThemeColor.init(hex:)), trend: ThemeColor(hex: trend.light))
        let darkPalette = ColorTheme.Palette(
            gradient: (dark ?? light).map(ThemeColor.init(hex:)),
            trend: ThemeColor(hex: trend.dark))
        theme = ColorTheme(
            presetID: id, light: lightPalette, dark: darkPalette, mapping: mapping, meter: meter)
    }

    public static func preset(id: String?) -> ThemePreset? { all.first { $0.id == id } }

    /// The single-green look the app shipped with: the green at the level opacities over
    /// each appearance's background, so tiles match the earlier rendering exactly.
    public static let slopGreen: ThemePreset = {
        func ramp(_ hex: UInt32, over background: ThemeColor) -> [ThemeColor] {
            SlopTheme.levelOpacities.map {
                ThemeColor(hex: hex).blended(over: background, opacity: $0)
            }
        }
        return ThemePreset(
            id: "slop-green", name: "Slop Green", isColorblindSafe: false,
            theme: ColorTheme(
                presetID: "slop-green",
                light: .init(
                    gradient: ramp(0x116329, over: SlopTheme.lightBackground),
                    accent: ThemeColor(hex: 0x116329), trend: ThemeColor(hex: 0x8A5C00)),
                dark: .init(
                    gradient: ramp(0x2EA043, over: SlopTheme.darkBackground),
                    accent: ThemeColor(hex: 0x2EA043), trend: ThemeColor(hex: 0xD29922))))
    }()

    private init(id: String, name: String, isColorblindSafe: Bool, theme: ColorTheme) {
        self.id = id
        self.name = name
        self.isColorblindSafe = isColorblindSafe
        self.theme = theme
    }

    public static let all: [ThemePreset] = [
        slopGreen,
        ThemePreset(
            id: "github", name: "GitHub", light: [0x9BE9A8, 0x40C463, 0x30A14E, 0x216E39],
            dark: [0x0E4429, 0x006D32, 0x26A641, 0x39D353]),
        ThemePreset(
            id: "electric", name: "Electric", light: [0x7DD3FC, 0x38BDF8, 0x6366F1, 0x7C3AED],
            dark: [0x1E3A8A, 0x2563EB, 0x38BDF8, 0xA78BFA], trend: (0xBE185D, 0xF472B6)),
        ThemePreset(
            id: "vibe-coded", name: "Vibe Coded", light: [0xC4B5FD, 0xA855F7, 0xD946EF, 0xDB2777],
            dark: [0x4C1D95, 0x7C3AED, 0xC026D3, 0xF472B6], trend: (0x0369A1, 0x38BDF8)),
        ThemePreset(
            id: "rainbow", name: "Rainbow",
            light: [0xE5484D, 0xF76B15, 0xFFC53D, 0x46A758, 0x0090FF, 0x3E63DD, 0x8E4EC6],
            trend: (0x1C2024, 0xEDEEF0), mapping: .continuous, meter: .gradient),
        ThemePreset(
            id: "sunset", name: "Sunset", light: [0xFFD166, 0xF4845F, 0xE0457B, 0x9D2B6B],
            dark: [0x6B2149, 0xC23A6B, 0xF4845F, 0xFFD166], trend: (0x5B21B6, 0xA78BFA)),
        ThemePreset(
            id: "ocean", name: "Ocean", light: [0x99E2E0, 0x2EA8C9, 0x1F6FB5, 0x1B3F8B],
            dark: [0x0F3B5F, 0x1F6FB5, 0x2EA8C9, 0x7FDBDA]),
        ThemePreset(
            id: "halloween", name: "Halloween", light: [0xFFEE4A, 0xFFC501, 0xFE9600, 0x631C03],
            dark: [0x631C03, 0xBD561D, 0xFA7A18, 0xFDDF68], trend: (0x5B21B6, 0xA78BFA)),
        ThemePreset(
            id: "mono", name: "Mono", isColorblindSafe: true,
            light: [0xC4C4C4, 0x8E8E8E, 0x5A5A5A, 0x2B2B2B],
            dark: [0x3A3A3A, 0x6B6B6B, 0xA0A0A0, 0xE0E0E0]),
        ThemePreset(
            id: "viridis", name: "Viridis", isColorblindSafe: true,
            light: [0xFDE725, 0x35B779, 0x31688E, 0x440154],
            dark: [0x440154, 0x31688E, 0x35B779, 0xFDE725], trend: (0xB4231C, 0xFF8A65)),
        ThemePreset(
            id: "cividis", name: "Cividis", isColorblindSafe: true,
            light: [0xFFEA46, 0xA69D75, 0x575C6D, 0x00204D],
            dark: [0x00204D, 0x575C6D, 0xA69D75, 0xFFEA46], trend: (0xB4231C, 0xFF8A65)),
    ]
}

/// Plain-language warnings for a theme. They advise; they never block a choice.
public enum ThemeAdvice: Equatable, Sendable {
    /// Two neighboring levels are hard to tell apart in this appearance.
    case similarLevels(isDark: Bool)
    /// Lightness does not rise (dark) or fall (light) steadily, so the grid view, which has
    /// no numbers, may not read as more and less.
    case unorderedLightness(isDark: Bool)
    /// The lowest level nearly disappears into the background.
    case faintLowLevel(isDark: Bool)

    public var message: String {
        let mode = { (dark: Bool) in dark ? "In dark mode" : "In light mode" }
        switch self {
        case .similarLevels(let dark):
            return "\(mode(dark)), some neighboring levels look alike."
        case .unorderedLightness(let dark):
            return
                "\(mode(dark)), colors don't go steadily lighter or darker, so the grid may be "
                + "hard to read without its numbers. Hover a day to see its count."
        case .faintLowLevel(let dark):
            return "\(mode(dark)), the lowest level is hard to see on the background."
        }
    }

    /// Minimum contrast between neighboring level fills.
    static let neighborContrast = 1.15
    /// Minimum contrast of level 1 on the background.
    static let lowLevelContrast = 1.2
    /// Lightness may step back this much between neighbors before it counts as unordered.
    static let lightnessTolerance = 0.02

    public static func check(_ theme: ColorTheme) -> [ThemeAdvice] {
        let resolved = theme.resolved()
        var advice: [ThemeAdvice] = []
        for isDark in [false, true] {
            let appearance = resolved.appearance(isDark: isDark)
            let fills = (1...4).map(appearance.fill(level:))
            if zip(fills, fills.dropFirst()).contains(where: {
                $0.contrast(with: $1) < neighborContrast
            }) {
                advice.append(.similarLevels(isDark: isDark))
            }
            // Light appearance reads more as darker; dark appearance as brighter.
            let lightness = appearance.gradient.map(\.lightness)
            let steps = zip(lightness, lightness.dropFirst()).map { isDark ? $1 - $0 : $0 - $1 }
            if steps.contains(where: { $0 < -lightnessTolerance }) {
                advice.append(.unorderedLightness(isDark: isDark))
            }
            if fills[0].contrast(with: appearance.background) < lowLevelContrast {
                advice.append(.faintLowLevel(isDark: isDark))
            }
        }
        return advice
    }
}
