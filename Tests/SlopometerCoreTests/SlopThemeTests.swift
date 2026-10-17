import SlopometerCore
import Testing

@Suite("Palette contrast")
struct SlopThemeTests {
    let theme = SlopTheme.standard

    @Test func contrastMathMatchesKnownWCAGValues() {
        #expect(abs(ThemeColor.white.contrast(with: .black) - 21) < 0.001)
        #expect(abs(ThemeColor(hex: 0x777777).contrast(with: .white) - 4.48) < 0.01)
    }

    @Test func activityTextAndFillsMeetWCAGTargetsInBothAppearances() {
        for appearance in [theme.light, theme.dark] {
            let background = appearance.background
            #expect(appearance.activityText.contrast(with: background) >= 4.5)
            #expect(appearance.activity.contrast(with: background) >= 3)
            #expect(appearance.trend.contrast(with: background) >= 4.5)
        }
        // Light appearance is darker than the earlier rgb(0.18, 0.63, 0.26).
        let earlier = ThemeColor(red: 0.18, green: 0.63, blue: 0.26)
        #expect(theme.light.activity.luminance < earlier.luminance)
    }

    @Test func everyTileLevelHasAReadableNumberAndDistinctNeighbors() {
        for appearance in [theme.light, theme.dark] {
            var previous: ThemeColor?
            for level in 1...4 {
                let fill = appearance.fill(level: level)
                let number: ThemeColor = appearance.numberIsLight(level: level) ? .white : .black
                #expect(fill.contrast(with: number) >= 4.5, "level \(level)")
                if let previous { #expect(fill.contrast(with: previous) >= 1.3, "level \(level)") }
                previous = fill
            }
        }
    }
}
