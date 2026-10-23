import AppKit
import Charts
import SlopometerCore
import SwiftUI
import WidgetKit

/// Renders a snapshot's points. Shared by the app window and the widget so both agree.
struct SlopChart: View {
    let points: [DashboardSnapshot.Point]
    let style: ChartStyle
    let unit: String
    var showsAverage = true
    /// The average's legend label, such as "7-day average".
    var averageLabel = "Average"
    var compact = false
    var selection: Binding<CalendarDay?>? = nil
    /// Caps the grid's height; nil lets it use all the height it is offered.
    var gridMaxHeight: CGFloat? = nil

    var body: some View {
        switch style {
        case .grid:
            HeatmapGrid(
                points: points, unit: unit, selection: selection, maxHeight: gridMaxHeight)
        case .columns, .line:
            TrendChart(
                points: points, style: style, unit: unit, showsAverage: showsAverage,
                averageLabel: averageLabel, compact: compact, selection: selection)
        }
    }
}

/// Theme-independent colors and the level math. Themed colors come from the environment's
/// `slopColors`, set at each window, panel, and widget root with `slopTheme(_:)`, so views
/// here render the person's theme in the app and in widgets alike.
enum SlopPalette {
    static let unknown = Color.secondary.opacity(0.25)
    static let track = Color.secondary.opacity(0.18)

    /// GitHub-style levels 0–4, scaled to the busiest visible day.
    static func level(_ count: Int, max: Int) -> Int { SlopTheme.level(count, max: max) }

    /// Level fills for widgets the desktop draws in one color (unfocused or tinted): white
    /// at a fixed opacity per level, so levels never depend on the hue's brightness.
    static func monochromeFill(level: Int) -> Color {
        Color.white.opacity([0.12, 0.3, 0.5, 0.75, 1][Swift.min(Swift.max(level, 0), 4)])
    }
}

extension Color {
    init(_ color: ThemeColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}

extension NSColor {
    convenience init(_ color: ThemeColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
}

private struct HeatmapGrid: View {
    let points: [DashboardSnapshot.Point]
    let unit: String
    let selection: Binding<CalendarDay?>?

    let maxHeight: CGFloat?
    @Environment(\.slopColors) private var colors

    var body: some View {
        let weeks = Self.weeks(points)
        let busiest = points.compactMap(\.count).max() ?? 0
        VStack(alignment: .leading, spacing: 8) {
            WeekGridLayout(columns: weeks.count, gap: 2, maxHeight: maxHeight) {
                ForEach(weeks.indices, id: \.self) { column in
                    ForEach(0..<7, id: \.self) { row in
                        if let point = weeks[column][row] {
                            cell(point, busiest: busiest)
                        } else {
                            Color.clear
                        }
                    }
                }
                // Rows are Sunday-first, so the symbols line up by index. Like GitHub,
                // only every other weekday is named.
                ForEach(0..<7, id: \.self) { row in
                    Text(row % 2 == 1 ? Calendar.current.shortWeekdaySymbols[row] : "")
                }
                ForEach(Array(Self.monthLabels(weeks).enumerated()), id: \.offset) { label in
                    Text(label.element ?? "")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            legend(busiest: busiest)
        }
    }

    /// Explains the shades and outlines: the scale is relative to the busiest day shown.
    private func legend(busiest: Int) -> some View {
        HStack(spacing: 14) {
            ShadeScale(includesEmpty: true)
            if busiest > 0 {
                Text("Busiest day: \(busiest) \(unit)")
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
                    .frame(width: 10, height: 10)
                Text("Today, so far")
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(SlopPalette.unknown, style: StrokeStyle(lineWidth: 1, dash: [2]))
                    .frame(width: 10, height: 10)
                Text("No data")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func cell(_ point: DashboardSnapshot.Point, busiest: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        let label = HeatmapLabel.describe(point, unit: unit)
        Group {
            if let count = point.count {
                // In tinted desktop widgets the levels survive as opacity of the accent.
                shape.fill(colors.fill(count: count, busiest: busiest))
                    .widgetAccentable()
            } else {
                shape.strokeBorder(SlopPalette.unknown, style: StrokeStyle(lineWidth: 1, dash: [2]))
            }
        }
        .overlay {
            // The selected day gets a heavier outline than today's, so the two never look alike.
            if selection?.wrappedValue == point.day {
                shape.strokeBorder(Color.primary, lineWidth: 2)
            } else if point.isIncomplete {
                shape.strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            }
        }
        .help(label)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(selection == nil ? [] : .isButton)
        .onTapGesture { selection?.wrappedValue = point.day }
    }

    /// Columns of Sunday-first weeks, like GitHub's calendar.
    static func weeks(_ points: [DashboardSnapshot.Point]) -> [[DashboardSnapshot.Point?]] {
        guard let first = points.first else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let weekday = calendar.component(.weekday, from: first.day.start(in: calendar.timeZone)) - 1
        var cells: [DashboardSnapshot.Point?] = Array(repeating: nil, count: weekday) + points
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// One label per column: the abbreviated month above the first week holding a new
    /// month's day, nil elsewhere. The first column's label is dropped when the next month
    /// starts within three weeks, so the two never overlap.
    static func monthLabels(_ weeks: [[DashboardSnapshot.Point?]]) -> [String?] {
        var labels: [String?] = []
        var previous: (year: Int, month: Int)?
        for week in weeks {
            let first = week.compactMap { $0 }.first { point in
                previous.map { (point.day.year, point.day.month) != ($0.year, $0.month) } ?? true
            }
            if let day = first?.day {
                previous = (day.year, day.month)
                labels.append(
                    day.start(in: .current).formatted(.dateTime.month(.abbreviated)))
            } else {
                labels.append(nil)
            }
        }
        if labels.count > 1, labels[0] != nil,
            labels[1..<min(labels.count, 4)].contains(where: { $0 != nil })
        {
            labels[0] = nil
        }
        return labels
    }
}

/// Less-to-more swatches in the theme's colors: its four levels, or its gradient when days
/// map smoothly. The grid includes the empty tile; columns draw nothing for empty days.
struct ShadeScale: View {
    var includesEmpty = false
    @Environment(\.slopColors) private var colors

    var body: some View {
        HStack(spacing: 4) {
            Text("Less")
            HStack(spacing: 2) {
                if includesEmpty { swatch(SlopColors.empty) }
                switch colors.appearance.mapping {
                case .levels:
                    ForEach(1...4, id: \.self) { swatch(colors.fill(level: $0)) }
                case .continuous:
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: colors.gradient, startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: 46, height: 10)
                }
            }
            Text("More")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shades run from less to more activity")
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
    }
}

/// Lays cells out column by column, seven per week, with square cells sized from the
/// width actually offered. It never reports more width than proposed, so a long range
/// cannot widen its container, and its height follows the cells so short ranges leave
/// no empty space below.
///
/// Subviews come in order: `columns × 7` cells, then seven weekday labels placed left of
/// their rows, then one month label per column placed above it.
private struct WeekGridLayout: Layout {
    let columns: Int
    let gap: CGFloat
    let maxHeight: CGFloat?

    /// Used only when no width is proposed. Small enough that a full year (54 weeks) stays
    /// narrower than the app window's minimum content width.
    private static let idealSide: CGFloat = 8
    /// Space between the labels and the cells.
    private static let labelGap: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let insets = insets(subviews)
        let side = side(width: proposal.width, height: proposal.height, insets: insets)
        return CGSize(
            width: insets.width + span(side, count: columns),
            height: insets.height + span(side, count: 7))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let insets = insets(subviews)
        let side = side(width: bounds.width, height: bounds.height, insets: insets)
        let cell = ProposedViewSize(width: side, height: side)
        let origin = CGPoint(x: bounds.minX + insets.width, y: bounds.minY + insets.height)
        let cellCount = columns * 7
        for (index, subview) in subviews.enumerated() {
            if index < cellCount {
                let column = CGFloat(index / 7)
                let row = CGFloat(index % 7)
                subview.place(
                    at: CGPoint(
                        x: origin.x + column * (side + gap), y: origin.y + row * (side + gap)),
                    proposal: cell)
            } else if index < cellCount + 7 {
                let row = CGFloat(index - cellCount)
                subview.place(
                    at: CGPoint(x: bounds.minX, y: origin.y + row * (side + gap) + side / 2),
                    anchor: .leading, proposal: .unspecified)
            } else {
                // Kept inside the trailing edge when a month starts in the last weeks.
                let column = CGFloat(index - cellCount - 7)
                let width = subview.sizeThatFits(.unspecified).width
                let x = min(origin.x + column * (side + gap), bounds.maxX - width)
                subview.place(
                    at: CGPoint(x: max(x, origin.x), y: bounds.minY), proposal: .unspecified)
            }
        }
    }

    /// The weekday column's width and the month row's height, each with its gap.
    private func insets(_ subviews: Subviews) -> CGSize {
        let cellCount = columns * 7
        guard subviews.count > cellCount else { return .zero }
        // Both slices must be `Range<Int>`. `Subviews` also has a subscript taking any
        // `Sequence` of indices, and Swift picks that one for `n...`, an endless sequence:
        // SwiftUI then reads past the last subview and the app traps on launch (1.0.5).
        let labelEnd = min(cellCount + 7, subviews.count)
        let rows = subviews[cellCount..<labelEnd]
        let months = subviews[labelEnd..<subviews.count]
        let width = rows.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let height = months.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(
            width: width > 0 ? width + Self.labelGap : 0,
            height: height > 0 ? height + Self.labelGap : 0)
    }

    private func side(width: CGFloat?, height: CGFloat?, insets: CGSize) -> CGFloat {
        let count = CGFloat(max(columns, 1))
        let heightLimit = min(height ?? .infinity, maxHeight ?? .infinity) - insets.height
        let byWidth =
            width.map { ($0 - insets.width - gap * (count - 1)) / count } ?? Self.idealSide
        let byHeight = heightLimit.isFinite ? (heightLimit - gap * 6) / 7 : .infinity
        return max(1, min(byWidth, byHeight))
    }

    private func span(_ side: CGFloat, count: Int) -> CGFloat {
        CGFloat(count) * side + CGFloat(max(count - 1, 0)) * gap
    }
}

/// One wording for a day's value, shared by tooltips, VoiceOver, and the detail header.
enum HeatmapLabel {
    static func describe(_ point: DashboardSnapshot.Point, unit: String) -> String {
        let date = point.day.start(in: .current).formatted(date: .abbreviated, time: .omitted)
        let value = point.count.map { "\($0) \(unit)" } ?? "unknown"
        return "\(date): \(value)\(point.isIncomplete ? " so far (today, incomplete)" : "")"
    }

    /// The moving average on a day, for VoiceOver on line and column charts.
    static func describeAverage(
        _ point: DashboardSnapshot.Point, _ average: Double, unit: String
    ) -> String {
        let date = point.day.start(in: .current).formatted(date: .abbreviated, time: .omitted)
        return
            "\(date): average \(average.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }
}

private struct TrendChart: View {
    let points: [DashboardSnapshot.Point]
    let style: ChartStyle
    let unit: String
    let showsAverage: Bool
    let averageLabel: String
    let compact: Bool
    let selection: Binding<CalendarDay?>?
    @Environment(\.slopColors) private var colors
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Unfocused or tinted desktop widgets draw in one color; full white keeps the marks
    /// at full strength there instead of the accent's luminance.
    private var markColor: Color {
        renderingMode == .fullColor ? colors.mark : .white
    }

    /// A column's color: the day's fill from the theme's gradient in full color, so bars
    /// and the calendar agree; full white when the desktop draws in one color.
    private func barColor(_ count: Int, busiest: Int) -> Color {
        renderingMode == .fullColor ? colors.fill(count: count, busiest: busiest) : .white
    }

    var body: some View {
        if compact {
            chart
        } else {
            VStack(alignment: .leading, spacing: 8) {
                chart
                legend
            }
        }
    }

    /// Drawn by hand rather than by Swift Charts: columns take each day's shade from the
    /// gradient, so a single "Daily" color swatch would contradict most of the bars.
    private var legend: some View {
        HStack(spacing: 14) {
            if style == .columns {
                HStack(spacing: 6) {
                    Text("Daily")
                    ShadeScale()
                }
            } else {
                HStack(spacing: 4) {
                    Capsule().fill(markColor).frame(width: 16, height: 2)
                    Text("Daily")
                }
            }
            if showsAverage, points.contains(where: { $0.average != nil }) {
                HStack(spacing: 4) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 1))
                        path.addLine(to: CGPoint(x: 18, y: 1))
                    }
                    .stroke(colors.average, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 18, height: 2)
                    Text(averageLabel)
                }
            }
            if style == .columns, points.contains(where: \.isIncomplete) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(colors.mark.opacity(0.4))
                        .frame(width: 6, height: 10)
                    Text("Today, so far")
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var chart: some View {
        let busiest = points.compactMap(\.count).max() ?? 0
        Chart {
            ForEach(points) { point in
                let date = point.day.start(in: .current)
                if let count = point.count {
                    if style == .columns {
                        BarMark(x: .value("Day", date, unit: .day), y: .value(unit, count))
                            .foregroundStyle(
                                barColor(count, busiest: busiest)
                                    .opacity(point.isIncomplete ? 0.4 : 1)
                            )
                            .accessibilityLabel(HeatmapLabel.describe(point, unit: unit))
                    } else {
                        LineMark(x: .value("Day", date, unit: .day), y: .value(unit, count))
                            .foregroundStyle(by: .value("Series", "Daily"))
                            .interpolationMethod(.linear)
                            .accessibilityLabel(HeatmapLabel.describe(point, unit: unit))
                    }
                }
                if showsAverage, let average = point.average {
                    LineMark(x: .value("Day", date, unit: .day), y: .value(unit, average))
                        .foregroundStyle(by: .value("Series", "Average"))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .accessibilityLabel(
                            HeatmapLabel.describeAverage(point, average, unit: unit))
                }
                if selection?.wrappedValue == point.day {
                    RuleMark(x: .value("Day", date, unit: .day))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
            }
        }
        .chartForegroundStyleScale([
            "Daily": markColor, "Average": colors.average,
        ])
        .chartLegend(.hidden)
        .chartYAxisLabel(compact ? "" : unit)
        .chartYAxis {
            // Compact charts keep the scale but drop gridlines so the marks stand out.
            AxisMarks(values: .automatic(desiredCount: compact ? 3 : 5)) { _ in
                if !compact {
                    AxisGridLine()
                    AxisTick()
                }
                AxisValueLabel()
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartXAxis(compact ? .hidden : .automatic)
        .chartOverlay { proxy in
            if let selection {
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            let origin = proxy.plotFrame.map { geometry[$0].origin } ?? .zero
                            if let date: Date = proxy.value(atX: location.x - origin.x) {
                                selection.wrappedValue = CalendarDay.containing(date, in: .current)
                            }
                        }
                }
            }
        }
    }
}
