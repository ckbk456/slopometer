import Foundation

/// A named view of the dashboard: what is counted and where, how it is charted, its
/// colors, and the daily quota. The account, tokens, timezone, widgets, and the
/// light/dark choice are shared by every configuration.
public struct SavedConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var metric: Metric
    /// Empty means all readable repositories.
    public var repositories: [String]
    public var chartStyle: ChartStyle
    public var rangeDays: Int
    public var averageWindow: Int
    public var theme: ColorTheme
    /// Nil keeps the quota off.
    public var goal: Goal?

    /// Captures the configuration the settings show now.
    public init(id: String = UUID().uuidString, name: String, settings: DashboardSettings) {
        self.id = id
        self.name = name
        metric = settings.metric
        repositories = settings.repositories
        chartStyle = settings.chartStyle
        rangeDays = settings.rangeDays
        averageWindow = settings.averageWindow
        theme = settings.theme
        goal = settings.goal
    }

    /// Missing keys keep the defaults, so adding a field never discards saved ones.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DashboardSettings()
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        metric = try container.decodeIfPresent(Metric.self, forKey: .metric) ?? defaults.metric
        repositories =
            try container.decodeIfPresent([String].self, forKey: .repositories)
            ?? defaults.repositories
        chartStyle =
            try container.decodeIfPresent(ChartStyle.self, forKey: .chartStyle)
            ?? defaults.chartStyle
        rangeDays =
            try container.decodeIfPresent(Int.self, forKey: .rangeDays) ?? defaults.rangeDays
        averageWindow =
            try container.decodeIfPresent(Int.self, forKey: .averageWindow)
            ?? defaults.averageWindow
        theme = try container.decodeIfPresent(ColorTheme.self, forKey: .theme) ?? defaults.theme
        goal = try container.decodeIfPresent(Goal.self, forKey: .goal)
    }

    /// The settings with this configuration's values; everything shared is kept.
    public func applied(to settings: DashboardSettings) -> DashboardSettings {
        var settings = settings
        settings.metric = metric
        settings.repositories = repositories
        settings.chartStyle = chartStyle
        settings.rangeDays = rangeDays
        settings.averageWindow = averageWindow
        settings.theme = theme
        settings.goal = goal
        settings.configurationID = id
        return settings
    }

    /// Whether the settings show this configuration without edits.
    public func matches(_ settings: DashboardSettings) -> Bool {
        Self(id: id, name: name, settings: settings) == self
    }
}

extension DashboardSettings {
    /// The configuration last chosen or saved, while it still exists.
    public var configuration: SavedConfiguration? {
        savedConfigurations.first { $0.id == configurationID }
    }

    /// The chosen configuration, if the settings have been changed since it was chosen.
    public var configurationIsEdited: Bool {
        configuration.map { !$0.matches(self) } ?? false
    }
}
