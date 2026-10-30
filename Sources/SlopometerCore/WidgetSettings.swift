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
    /// The daily quota when one is set, otherwise today's count.
    case quota
    case today

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quota: "Daily quota"
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
    /// Columns and line only; the grid always shows the `WidgetSettings.calendarWeeks` calendar.
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
    /// Rows of the large widget's calendar grid: whole weeks, the current one last.
    public static let calendarWeeks = 5
    /// Column and line windows offered for the large widget.
    public static let windows = [30, 90]
    /// The shortest series history the snapshot builds, so every size's window is covered
    /// whatever the dashboard range is.
    public static let minimumHistoryDays = max(stripDays, calendarWeeks * 7, windows.max() ?? 0)

    /// Days the calendar grid shows through `today`: the earlier full weeks plus the current
    /// week up to today, so the first day starts a week and rows align with weekdays.
    /// - Parameter firstWeekday: 1 is Sunday, as in `Calendar.firstWeekday`.
    public static func calendarDays(through today: CalendarDay, firstWeekday: Int) -> Int {
        (calendarWeeks - 1) * 7 + today.daysSinceWeekStart(firstWeekday: firstWeekday) + 1
    }

    /// Lays days out as calendar rows of seven, columns in weekday order from
    /// `firstWeekday`. Days before the first point and after the last are nil, so future
    /// days are empty rather than zero. Keeps the last `calendarWeeks` rows.
    public static func calendarRows<Day>(
        _ days: [Day], firstWeekday: Int, day: (Day) -> CalendarDay
    ) -> [[Day?]] {
        guard let first = days.first else { return [] }
        let lead = day(first).daysSinceWeekStart(firstWeekday: firstWeekday)
        var cells: [Day?] = Array(repeating: nil, count: lead) + days
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
        return Array(rows.suffix(calendarWeeks))
    }

    public var small = WidgetPanelSettings()
    public var medium = WidgetPanelSettings()
    public var large = WidgetPanelSettings()

    public init() {}

    /// Settings saved before widgets were configurable followed the dashboard; keep that.
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
    /// Days of series a size shows through `today`; small shows none.
    func days(for size: WidgetSize, through today: CalendarDay, firstWeekday: Int) -> Int {
        switch size {
        case .small: 0
        case .medium: WidgetSettings.stripDays
        case .large:
            chartStyle == .grid
                ? WidgetSettings.calendarDays(through: today, firstWeekday: firstWeekday)
                : (WidgetSettings.windows.contains(windowDays) ? windowDays : 90)
        }
    }
}

extension CalendarDay {
    /// 1 for Sunday through 7 for Saturday, like `Calendar.component(.weekday, from:)`.
    public var weekday: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.component(.weekday, from: start(in: calendar.timeZone))
    }

    /// 0 when this day starts a week beginning on `firstWeekday` (1 is Sunday), up to 6.
    public func daysSinceWeekStart(firstWeekday: Int) -> Int {
        ((weekday - firstWeekday) % 7 + 7) % 7
    }
}
