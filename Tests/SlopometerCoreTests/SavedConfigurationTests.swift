import Foundation
import SlopometerCore
import Testing

@Suite("Saved configurations")
struct SavedConfigurationTests {
    var settings: DashboardSettings {
        var settings = DashboardSettings()
        settings.login = "octocat"
        settings.timeZoneID = "Asia/Ho_Chi_Minh"
        settings.metric = .prsMerged
        settings.repositories = ["octo/app"]
        settings.chartStyle = .columns
        settings.rangeDays = 30
        settings.averageWindow = 30
        settings.goal = Goal(metric: .prsMerged, target: 5)
        return settings
    }

    @Test func applyingRestoresTheViewAndKeepsSharedSettings() {
        let saved = SavedConfiguration(name: "Work", settings: settings)
        var other = DashboardSettings()
        other.login = "someone"
        other.timeZoneID = "Europe/Paris"
        other.appearance = .dark
        let applied = saved.applied(to: other)

        #expect(applied.metric == .prsMerged)
        #expect(applied.repositories == ["octo/app"])
        #expect(applied.chartStyle == .columns)
        #expect(applied.rangeDays == 30)
        #expect(applied.averageWindow == 30)
        #expect(applied.goal == Goal(metric: .prsMerged, target: 5))
        #expect(applied.configurationID == saved.id)
        #expect(applied.login == "someone")
        #expect(applied.timeZoneID == "Europe/Paris")
        #expect(applied.appearance == .dark)
        #expect(applied.widgets == other.widgets)
    }

    @Test func aConfigurationWithoutAQuotaTurnsItOff() {
        var base = settings
        base.goal = nil
        let saved = SavedConfiguration(name: "Calendar", settings: base)
        #expect(saved.applied(to: settings).goal == nil)
    }

    @Test func editsAreDetectedUntilUndone() {
        var current = settings
        current.savedConfigurations = [SavedConfiguration(name: "Work", settings: current)]
        current = current.savedConfigurations[0].applied(to: current)
        #expect(current.configuration?.name == "Work")
        #expect(!current.configurationIsEdited)

        current.rangeDays = 365
        #expect(current.configurationIsEdited)
        current.rangeDays = 30
        #expect(!current.configurationIsEdited)
        // Shared settings are not part of a configuration.
        current.appearance = .light
        current.density = .compact
        #expect(!current.configurationIsEdited)
    }

    @Test func aDeletedConfigurationIsNoLongerChosen() {
        var current = settings
        let saved = SavedConfiguration(name: "Work", settings: current)
        current.savedConfigurations = [saved]
        current = saved.applied(to: current)
        current.savedConfigurations = []
        #expect(current.configuration == nil)
        #expect(!current.configurationIsEdited)
    }

    @Test func settingsWithoutConfigurationsStillDecode() throws {
        let data = Data(#"{"login":"octocat","metric":"prsOpened"}"#.utf8)
        let decoded = try JSONDecoder().decode(DashboardSettings.self, from: data)
        #expect(decoded.savedConfigurations.isEmpty)
        #expect(decoded.configurationID == nil)
        #expect(decoded.density == .comfortable)
        #expect(decoded.metric == .prsOpened)
    }

    @Test func aConfigurationMissingNewerFieldsKeepsDefaults() throws {
        let data = Data(#"{"id":"a","name":"Old","metric":"prsMerged"}"#.utf8)
        let decoded = try JSONDecoder().decode(SavedConfiguration.self, from: data)
        #expect(decoded.metric == .prsMerged)
        #expect(decoded.rangeDays == DashboardSettings().rangeDays)
        #expect(decoded.goal == nil)
    }

    @Test func roundTripsThroughSettings() throws {
        var current = settings
        current.savedConfigurations = [SavedConfiguration(name: "Work", settings: current)]
        current.configurationID = current.savedConfigurations[0].id
        let decoded = try JSONDecoder().decode(
            DashboardSettings.self, from: JSONEncoder().encode(current))
        #expect(decoded == current)
    }
}
