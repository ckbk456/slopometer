import Foundation

/// The system widget sizes Slopometer supports, each configured on its own.
public enum WidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// What a widget leads with.
public enum WidgetHeadline: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The daily PR quota when one is set, otherwise today's count.
    case quota
    case today

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quota: "Daily PR quota"
        case .today: "Today's count"
        }
    }
}

/// One widget size's choices. Sizes ignore what they cannot show: small has no chart,
/// and medium always shows its 7-day strip.
public struct WidgetPanelSettings: Codable, Equatable, Sendable {
    public var headline = WidgetHeadline.quota
    public var metric = Metric.contributions
    public var chartStyle = ChartStyle.grid
    /// Columns and line only; the grid always shows `WidgetSettings.gridDays`.
    public var windowDays = 90

    public init(
        headline: WidgetHeadline = .quota, metric: Metric = .contributions,
        chartStyle: ChartStyle = .grid, windowDays: Int = 90
    ) {
        self.headline = headline
        self.metric = metric
        self.chartStyle = chartStyle
        self.windowDays = windowDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        headline =
            try container.decodeIfPresent(WidgetHeadline.self, forKey: .headline)
            ?? defaults.headline
        metric = try container.decodeIfPresent(Metric.self, forKey: .metric) ?? defaults.metric
        chartStyle =
            try container.decodeIfPresent(ChartStyle.self, forKey: .chartStyle)
            ?? defaults.chartStyle
        windowDays =
            try container.decodeIfPresent(Int.self, forKey: .windowDays)
            ?? defaults.windowDays
    }
}

/// Per-size widget settings, independent of the dashboard's metric and view.
public struct WidgetSettings: Codable, Equatable, Sendable {
    /// The medium widget's tile strip.
    public static let stripDays = 7
    /// 26 weeks: the large widget's grid.
    public static let gridDays = 26 * 7
    /// Column and line windows offered for the large widget.
    public static let windows = [30, 90]

    public var small = WidgetPanelSettings()
    public var medium = WidgetPanelSettings()
    public var large = WidgetPanelSettings()

    public init() {}

    /// Settings saved before widgets were configurable followed the dashboard; keep that.
    public init(following metric: Metric, chartStyle: ChartStyle) {
        small.metric = metric
        medium.metric = metric
        large.metric = metric
        large.chartStyle = chartStyle
    }

    public subscript(size: WidgetSize) -> WidgetPanelSettings {
        get {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        set {
            switch size {
            case .small: small = newValue
            case .medium: medium = newValue
            case .large: large = newValue
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        small = try container.decodeIfPresent(WidgetPanelSettings.self, forKey: .small) ?? .init()
        medium =
            try container.decodeIfPresent(WidgetPanelSettings.self, forKey: .medium) ?? .init()
        large = try container.decodeIfPresent(WidgetPanelSettings.self, forKey: .large) ?? .init()
    }
}

extension WidgetPanelSettings {
    /// Days of series a size shows; small shows none.
    func days(for size: WidgetSize) -> Int {
        switch size {
        case .small: 0
        case .medium: WidgetSettings.stripDays
        case .large:
            chartStyle == .grid
                ? WidgetSettings.gridDays
                : (WidgetSettings.windows.contains(windowDays) ? windowDays : 90)
        }
    }
}
