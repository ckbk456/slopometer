import SlopometerCore
import SwiftUI
import WidgetKit

/// One widget size's content for a snapshot. The widget renders it, and the app's Widgets
/// tab previews it, so the preview is what the desktop shows.
struct WidgetContent: View {
    /// Nil when no readable snapshot exists.
    let snapshot: DashboardSnapshot?
    let size: WidgetSize
    /// The moment the widget shows, so the sync age can advance between snapshots.
    var now = Date()
    @Environment(\.slopColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            // Only the widget sees a stamped snapshot; the app's preview never shows this.
            if BuildStamp.differs(writer: snapshot?.writerBuild, reader: BuildStamp(bundle: .main))
            {
                Text("Widget build differs from app. Reopen Slopometer.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
    }

    private var content: some View {
        Group {
            if let snapshot, snapshot.tier != .notConfigured,
                let panel = snapshot.widget(size)
            {
                if panel.metric.requiresToken, snapshot.tier != .token {
                    message(
                        "\(panel.metric.title) needs a GitHub token",
                        detail: "Add one in Settings, or show Contributions instead."
                    )
                } else {
                    measured(snapshot, panel)
                }
            } else if snapshot == nil {
                message(
                    "No data yet", detail: "Open Slopometer to fill this in.")
            } else if snapshot?.tier == .notConfigured {
                message("Slopometer", detail: "Open the app and enter a GitHub username.")
            } else {
                message("Update Slopometer", detail: "Open the app to refresh this widget.")
            }
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.title3)
                .foregroundStyle(colors.markText)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text(title).font(.headline).lineLimit(2)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Each size shows what its own settings ask for, in a fixed window labeled in the footer.
    @ViewBuilder
    private func measured(_ snapshot: DashboardSnapshot, _ panel: DashboardSnapshot.Widget)
        -> some View
    {
        let quota = panel.headline == .quota ? snapshot.quota : nil
        switch size {
        case .small:
            VStack(alignment: .leading, spacing: 8) {
                headline(quota, panel)
                Spacer(minLength: 0)
                // A clock time keeps its width; a ticking relative age gets truncated here.
                Text("Synced \(syncTime(snapshot))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        case .medium:
            VStack(alignment: .leading, spacing: 8) {
                compactHeadline(quota, panel)
                Spacer(minLength: 0)
                WeekStrip(points: panel.points, unit: panel.unit)
                footer(snapshot, quota, panel)
            }
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                headline(quota, panel)
                largeChart(panel)
                footer(snapshot, quota, panel)
            }
        }
    }

    @ViewBuilder
    private func largeChart(_ panel: DashboardSnapshot.Widget) -> some View {
        if panel.points.isEmpty {
            Spacer(minLength: 0)
        } else if panel.chartStyle == .grid {
            CalendarGrid(points: panel.points, unit: panel.unit)
                .frame(maxHeight: .infinity)
        } else {
            SlopChart(
                points: panel.points, style: panel.chartStyle, unit: panel.unit,
                showsAverage: false, compact: true
            )
            .widgetAccentable()
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func headline(_ quota: DashboardSnapshot.Quota?, _ panel: DashboardSnapshot.Widget)
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            if let quota {
                quotaCount(quota)
                QuotaMeter(count: quota.count, target: quota.target, height: 6)
                Text("\(quota.unit) today")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text(panel.todayCount.map(String.init) ?? "–")
                    .font(countFont)
                    .monospacedDigit()
                Text("\(panel.unit) today so far")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One row for the medium widget, leaving its height to the week strip.
    private func compactHeadline(
        _ quota: DashboardSnapshot.Quota?, _ panel: DashboardSnapshot.Widget
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let quota {
                quotaCount(quota)
                VStack(alignment: .leading, spacing: 4) {
                    QuotaMeter(count: quota.count, target: quota.target, height: 5)
                    Text("\(quota.unit) today")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text(panel.todayCount.map(String.init) ?? "–")
                    .font(countFont)
                    .monospacedDigit()
                Text("\(panel.unit) today so far")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func quotaCount(_ quota: DashboardSnapshot.Quota) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(quota.count)").font(countFont)
            Text("/ \(quota.target)")
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
    }

    private var countFont: Font {
        .system(size: size == .small ? 36 : 30, weight: .semibold, design: .rounded)
    }

    /// Changing text on the left, the constant window label on the right, so the age's
    /// width never shifts anything. The age is fixed-width hours:minutes, not a ticking
    /// relative string. Names the chart's metric when it differs from the quota.
    private func footer(
        _ snapshot: DashboardSnapshot, _ quota: DashboardSnapshot.Quota?,
        _ panel: DashboardSnapshot.Widget
    ) -> some View {
        let window = panel.windowLabel
        let label =
            quota.map { $0.unit != panel.unit } == true
            ? "\(panel.metric.title), \(window.prefix(1).lowercased() + window.dropFirst())"
            : window
        return HStack(spacing: 8) {
            Text(SyncAgeLabel.text(synced: snapshot.lastSuccessfulSync, now: now))
            Spacer(minLength: 8)
            Text(label).layoutPriority(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func syncTime(_ snapshot: DashboardSnapshot) -> String {
        snapshot.lastSuccessfulSync?.formatted(date: .omitted, time: .shortened) ?? "never"
    }
}

/// The medium widget's last seven days: one tile per day with its count, so it reads
/// without color. Intensity uses the grid's levels; today is outlined.
private struct WeekStrip: View {
    let points: [DashboardSnapshot.Point]
    let unit: String

    var body: some View {
        let busiest = points.compactMap(\.count).max() ?? 0
        HStack(spacing: 5) {
            ForEach(points) { point in
                VStack(spacing: 3) {
                    DayTile(point: point, busiest: busiest)
                        .frame(height: 30)
                    WeekdayLabel(date: point.day.start(in: .current), isToday: point.isIncomplete)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HeatmapLabel.describe(point, unit: unit))
            }
        }
    }
}

/// The large widget's grid as a calendar: a column per weekday in the locale's order and a
/// row per week, the current week last. Tiles share the medium strip's look and fill the
/// height they are given; days after today are left empty.
private struct CalendarGrid: View {
    let points: [DashboardSnapshot.Point]
    let unit: String

    private static let gap: CGFloat = 4

    var body: some View {
        let calendar = Calendar.current
        let rows = WidgetSettings.calendarRows(
            points, firstWeekday: calendar.firstWeekday, day: \.day)
        let busiest = points.compactMap(\.count).max() ?? 0
        let today = rows.last?.lastIndex { $0?.isIncomplete == true }
        VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                ForEach(0..<7, id: \.self) { column in
                    WeekdayLabel(
                        symbol: Self.symbol(column, calendar: calendar),
                        isToday: column == today
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(0..<7, id: \.self) { column in
                        if let point = rows[row][column] {
                            DayTile(point: point, busiest: busiest, textStyle: .title3)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(HeatmapLabel.describe(point, unit: unit))
                        } else {
                            Color.clear.accessibilityHidden(true)
                        }
                    }
                }
                // Every row is flexible, so the rows split the height evenly with no gap.
                .frame(maxHeight: .infinity)
            }
        }
    }

    /// The column's abbreviated weekday, starting from the locale's first weekday.
    private static func symbol(_ column: Int, calendar: Calendar) -> String {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return symbols[(calendar.firstWeekday - 1 + column) % symbols.count]
    }
}

/// A weekday caption; today's is bold in the primary color, because its tile outline can
/// vanish on a bright tile when the desktop draws the widget in one color.
private struct WeekdayLabel: View {
    let text: Text
    let isToday: Bool

    init(date: Date, isToday: Bool) {
        text = Text(date, format: .dateTime.weekday(.abbreviated))
        self.isToday = isToday
    }

    init(symbol: String, isToday: Bool) {
        text = Text(symbol)
        self.isToday = isToday
    }

    var body: some View {
        text
            .font(.caption2.weight(isToday ? .bold : .regular))
            .foregroundStyle(isToday ? .primary : .secondary)
            .lineLimit(1)
    }
}

/// One day's tile with its count: the theme's fill for the day (levels or smooth), an en dash
/// for unknown, today outlined.
/// Shared by the medium strip, the large calendar, and the menu bar panel.
struct DayTile: View {
    let point: DashboardSnapshot.Point
    let busiest: Int
    var textStyle: Font.TextStyle = .callout
    @Environment(\.slopColors) private var colors
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        ZStack {
            if let count = point.count {
                let level = SlopPalette.level(count, max: busiest)
                let label = Text("\(count)")
                    .font(.system(textStyle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                if renderingMode == .fullColor {
                    shape.fill(colors.fill(count: count, busiest: busiest))
                    label.foregroundStyle(colors.number(count: count, busiest: busiest))
                } else if level >= 2 {
                    // Unfocused and tinted desktop widgets draw text and bright tiles in the
                    // same near-white, so from half brightness up the number is cut out of
                    // the tile and the desktop shows through it.
                    shape.fill(SlopPalette.monochromeFill(level: level))
                        .overlay { label.blendMode(.destinationOut) }
                        .compositingGroup()
                        .widgetAccentable()
                } else {
                    shape.fill(SlopPalette.monochromeFill(level: level)).widgetAccentable()
                    label
                }
            } else {
                shape.strokeBorder(SlopPalette.unknown, style: StrokeStyle(lineWidth: 1, dash: [2]))
                Text("–").font(.system(textStyle)).foregroundStyle(.secondary)
            }
            if point.isIncomplete {
                shape.strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
