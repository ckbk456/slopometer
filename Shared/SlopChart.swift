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
                compact: compact, selection: selection)
        }
    }
}

/// One fixed palette for every surface: green is measured activity, amber is the trend.
/// Controls are tinted with `mark` so they do not compete with the chart.
enum SlopPalette {
    static let mark = Color(red: 0.18, green: 0.63, blue: 0.26)
    static let average = Color(red: 0.86, green: 0.6, blue: 0.13)
    static let unknown = Color.secondary.opacity(0.25)
    static let track = Color.secondary.opacity(0.18)

    /// GitHub-style levels 0–4, scaled to the busiest visible day.
    static func level(_ count: Int, max: Int) -> Int {
        guard count > 0, max > 0 else { return 0 }
        return Swift.min(4, Swift.max(1, Int((Double(count) / Double(max) * 4).rounded(.up))))
    }

    static func fill(level: Int) -> Color {
        level == 0 ? Color.secondary.opacity(0.12) : mark.opacity(0.25 + 0.1875 * Double(level))
    }
}

private struct HeatmapGrid: View {
    let points: [DashboardSnapshot.Point]
    let unit: String
    let selection: Binding<CalendarDay?>?

    let maxHeight: CGFloat?

    var body: some View {
        let weeks = Self.weeks(points)
        let busiest = points.compactMap(\.count).max() ?? 0
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
        }
    }

    @ViewBuilder
    private func cell(_ point: DashboardSnapshot.Point, busiest: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        let label = HeatmapLabel.describe(point, unit: unit)
        Group {
            if let count = point.count {
                // In tinted desktop widgets the levels survive as opacity of the accent.
                shape.fill(SlopPalette.fill(level: SlopPalette.level(count, max: busiest)))
                    .widgetAccentable()
            } else {
                shape.strokeBorder(SlopPalette.unknown, style: StrokeStyle(lineWidth: 1, dash: [2]))
            }
        }
        .overlay {
            if point.isIncomplete || selection?.wrappedValue == point.day {
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
}

/// Lays cells out column by column, seven per week, with square cells sized from the
/// width actually offered. It never reports more width than proposed, so a long range
/// cannot widen its container, and its height follows the cells so short ranges leave
/// no empty space below.
private struct WeekGridLayout: Layout {
    let columns: Int
    let gap: CGFloat
    let maxHeight: CGFloat?

    /// Used only when no width is proposed. Small enough that a full year (54 weeks) stays
    /// narrower than the app window's minimum content width.
    private static let idealSide: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let side = side(width: proposal.width, height: proposal.height)
        return CGSize(width: span(side, count: columns), height: span(side, count: 7))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let side = side(width: bounds.width, height: bounds.height)
        let cell = ProposedViewSize(width: side, height: side)
        for (index, subview) in subviews.enumerated() {
            let column = CGFloat(index / 7)
            let row = CGFloat(index % 7)
            subview.place(
                at: CGPoint(
                    x: bounds.minX + column * (side + gap), y: bounds.minY + row * (side + gap)),
                proposal: cell)
        }
    }

    private func side(width: CGFloat?, height: CGFloat?) -> CGFloat {
        let count = CGFloat(max(columns, 1))
        let heightLimit = min(height ?? .infinity, maxHeight ?? .infinity)
        let byWidth = width.map { ($0 - gap * (count - 1)) / count } ?? Self.idealSide
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
}

private struct TrendChart: View {
    let points: [DashboardSnapshot.Point]
    let style: ChartStyle
    let unit: String
    let showsAverage: Bool
    let compact: Bool
    let selection: Binding<CalendarDay?>?

    var body: some View {
        Chart {
            ForEach(points) { point in
                let date = point.day.start(in: .current)
                if let count = point.count {
                    if style == .columns {
                        BarMark(x: .value("Day", date, unit: .day), y: .value(unit, count))
                            .foregroundStyle(SlopPalette.mark.opacity(point.isIncomplete ? 0.4 : 1))
                    } else {
                        LineMark(x: .value("Day", date, unit: .day), y: .value(unit, count))
                            .foregroundStyle(by: .value("Series", "Daily"))
                            .interpolationMethod(.linear)
                    }
                }
                if showsAverage, let average = point.average {
                    LineMark(x: .value("Day", date, unit: .day), y: .value(unit, average))
                        .foregroundStyle(by: .value("Series", "Average"))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
                if selection?.wrappedValue == point.day {
                    RuleMark(x: .value("Day", date, unit: .day))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
            }
        }
        .chartForegroundStyleScale(["Daily": SlopPalette.mark, "Average": SlopPalette.average])
        .chartLegend(compact ? .hidden : .automatic)
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
