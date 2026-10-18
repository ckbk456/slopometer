import Foundation
import SlopometerCore
import Testing

@Suite("Palette contrast")
struct SlopThemeTests {
    let theme = SlopTheme.standard

    @Test func contrastMathMatchesKnownWCAGValues() {
        #expect(abs(ThemeColor.white.contrast(with: .black) - 21) < 0.001)
        #expect(abs(ThemeColor(hex: 0x777777).contrast(with: .white) - 4.48) < 0.01)
    }

    @Test func accentTextAndFillsMeetWCAGTargetsInBothAppearances() {
        for appearance in [theme.light, theme.dark] {
            let background = appearance.background
            #expect(appearance.accentText.contrast(with: background) >= 4.5)
            #expect(appearance.accent.contrast(with: background) >= 3)
            #expect(appearance.trend.contrast(with: background) >= 4.5)
        }
    }

    @Test func standardIsSlopElectricWithNoAdvice() {
        #expect(ColorTheme.standard.presetID == "electric")
        #expect(ThemePreset.all.first?.name == "Slop Electric")
        #expect(ThemeAdvice.check(.standard).isEmpty)
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

@Suite("Color themes")
struct ColorThemeTests {
    @Test func hexRoundTripsAndRejectsGarbage() {
        #expect(ThemeColor(hexString: "#116329") == ThemeColor(hex: 0x116329))
        #expect(ThemeColor(hexString: "2ea043")?.hexString == "#2EA043")
        #expect(ThemeColor(hexString: "#12345") == nil)
        #expect(ThemeColor(hexString: "zzzzzz") == nil)
    }

    @Test func mixingHitsBothEndsAndStaysInGamut() {
        let red = ThemeColor(hex: 0xE5484D)
        let blue = ThemeColor(hex: 0x0090FF)
        #expect(red.mixed(with: blue, by: 0).contrast(with: red) < 1.001)
        #expect(red.mixed(with: blue, by: 1).contrast(with: blue) < 1.001)
        let middle = red.mixed(with: blue, by: 0.5)
        for c in [middle.red, middle.green, middle.blue] { #expect((0...1).contains(c)) }
    }

    @Test func readableReachesTheTargetOnBothBackgrounds() {
        let yellow = ThemeColor(hex: 0xFFEE4A)
        for background in [SlopTheme.lightBackground, SlopTheme.darkBackground] {
            #expect(yellow.readable(on: background).contrast(with: background) >= 4.5)
        }
        // Already readable colors are left alone.
        let green = ThemeColor(hex: 0x116329)
        #expect(green.readable(on: SlopTheme.lightBackground) == green)
    }

    @Test func levelsSampleTheGradientEvenly() {
        let rainbow = ThemePreset.preset(id: "rainbow")!.theme.resolved().light
        #expect(rainbow.fill(level: 1) == rainbow.gradient.first)
        #expect(rainbow.fill(level: 4).contrast(with: rainbow.gradient.last!) < 1.001)
        #expect(rainbow.color(at: 0.5).contrast(with: rainbow.gradient[3]) < 1.001)
    }

    @Test func continuousMappingGivesEachCountItsOwnColor() {
        var theme = ThemePreset.preset(id: "rainbow")!.theme
        theme.mapping = .continuous
        let appearance = theme.resolved().light
        #expect(appearance.fill(count: 0, busiest: 7) == nil)
        #expect(appearance.fill(count: 1, busiest: 7) == appearance.gradient.first)
        let colors = (1...7).compactMap { appearance.fill(count: $0, busiest: 7) }
        #expect(Set(colors).count == 7)
        #expect(appearance.fill(count: 1, busiest: 1) == appearance.color(at: 1))

        theme.mapping = .levels
        let levels = theme.resolved().light
        #expect(Set((1...7).compactMap { levels.fill(count: $0, busiest: 7) }).count == 4)
    }

    @Test func gradientMeterWalksFromFirstToLastColor() {
        let appearance = ThemePreset.preset(id: "rainbow")!.theme.resolved().light
        #expect(appearance.meterFill(tick: 0, of: 5) == appearance.gradient.first)
        #expect(
            appearance.meterFill(tick: 4, of: 5).contrast(with: appearance.gradient.last!) < 1.001)
        let accent = ColorTheme.standard.resolved().light
        #expect(accent.meterFill(tick: 2, of: 5) == accent.accent)
    }

    @Test func everyPresetHasReadableTextAndTrend() {
        #expect(Set(ThemePreset.all.map(\.id)).count == ThemePreset.all.count)
        for preset in ThemePreset.all {
            let resolved = preset.theme.resolved()
            for appearance in [resolved.light, resolved.dark] {
                let background = appearance.background
                #expect(appearance.accentText.contrast(with: background) >= 4.5, "\(preset.id)")
                #expect(appearance.trend.contrast(with: background) >= 3, "\(preset.id)")
                #expect(appearance.warning.contrast(with: background) >= 4.5, "\(preset.id)")
                #expect(
                    (2...ColorTheme.maxColors).contains(appearance.gradient.count), "\(preset.id)")
            }
        }
    }

    @Test func orderedPresetsGetNoLightnessWarning() {
        for id in ["electric", "github", "mono", "viridis", "cividis", "ocean"] {
            let advice = ThemeAdvice.check(ThemePreset.preset(id: id)!.theme)
            #expect(
                !advice.contains { if case .unorderedLightness = $0 { true } else { false } },
                "\(id)")
        }
        // The rainbow's hues jump in lightness; the editor says so rather than refusing.
        let rainbow = ThemeAdvice.check(ThemePreset.preset(id: "rainbow")!.theme)
        #expect(rainbow.contains(.unorderedLightness(isDark: false)))
    }

    @Test func nearlyIdenticalLevelsAreFlagged() {
        let gray = ThemeColor(hex: 0x808080)
        let flat = ColorTheme(light: .init(gradient: [gray, gray], trend: .black))
        let advice = ThemeAdvice.check(flat)
        #expect(advice.contains(.similarLevels(isDark: false)))
        #expect(advice.contains(.similarLevels(isDark: true)))
    }

    @Test func settingsWithoutAThemeDecodeToTheStandardTheme() throws {
        let data = Data(#"{"login":"octocat"}"#.utf8)
        let settings = try JSONDecoder().decode(DashboardSettings.self, from: data)
        #expect(settings.theme == .standard)

        var edited = settings
        edited.theme = ThemePreset.preset(id: "electric")!.theme
        edited.theme.presetID = nil
        let roundTrip = try JSONDecoder().decode(
            DashboardSettings.self, from: JSONEncoder().encode(edited))
        #expect(roundTrip.theme == edited.theme)
    }

    @Test func retiredSlopGreenDecodesToTheStandardTheme() throws {
        let data = Data(
            #"{"presetID":"slop-green","light":{"gradient":[],"trend":{"red":0,"green":0,"blue":0}}}"#
                .utf8)
        #expect(try JSONDecoder().decode(ColorTheme.self, from: data) == .standard)
        #expect(ThemePreset.preset(id: "slop-green") == nil)
    }

    @Test func degenerateGradientsStillResolve() {
        let single = ColorTheme(light: .init(gradient: [ThemeColor(hex: 0x0090FF)], trend: .black))
        #expect(single.resolved().light.gradient.count == 2)
        let empty = ColorTheme(light: .init(gradient: [], trend: .black))
        #expect(empty.resolved().dark.gradient.count == 2)
    }

    @Test func savedThemesTakeTheirIDAsThePresetID() {
        let saved = SavedTheme(name: "Mine", theme: ThemePreset.preset(id: "electric")!.theme)
        #expect(saved.theme.presetID == saved.id)
        #expect(SavedTheme(id: "fixed", name: "Mine", theme: .standard).theme.presetID == "fixed")
        #expect(SavedTheme(name: "A", theme: .standard).id != saved.id)
    }

    @Test func settingsWithoutAppearanceOrSavedThemesKeepDefaultsAndRoundTrip() throws {
        let data = Data(#"{"login":"octocat"}"#.utf8)
        let settings = try JSONDecoder().decode(DashboardSettings.self, from: data)
        #expect(settings.appearance == .system)
        #expect(settings.savedThemes.isEmpty)

        var edited = settings
        edited.appearance = .dark
        edited.savedThemes = [
            SavedTheme(name: "Mine", theme: .standard),
            SavedTheme(name: "Mine", theme: ThemePreset.preset(id: "electric")!.theme),
        ]
        let roundTrip = try JSONDecoder().decode(
            DashboardSettings.self, from: JSONEncoder().encode(edited))
        #expect(roundTrip == edited)
    }
}
