import Charts
import SlopometerCore
import SwiftUI

/// Renders a snapshot's points. Shared by the app window and the widget so both agree.
struct SlopChart: View {
    let points: [DashboardSnapshot.Point]
    let style: ChartStyle
    let unit: String
    var showsAverage = true
    var compact = false
    var selection: Binding<CalendarDay?>? = nil

    var body: some View {
        switch style {
        case .grid:
            HeatmapGrid(points: points, unit: unit, selection: selection)
        case .columns, .line:
            TrendChart(
                points: points, style: style, unit: unit, showsAverage: showsAverage,
                compact: compact, selection: selection)
        }
    }
}

enum SlopPalette {
    static let mark = Color.green
    static let average = Color.orange
    static let unknown = Color.secondary.opacity(0.25)

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

    var body: some View {
        let weeks = Self.weeks(points)
        let busiest = points.compactMap(\.count).max() ?? 0
        GeometryReader { geometry in
            let gap: CGFloat = 2
            let side = max(
                3,
                min(
                    (geometry.size.width - gap * CGFloat(weeks.count - 1))
                        / CGFloat(max(weeks.count, 1)),
                    (geometry.size.height - gap * 6) / 7))
            HStack(alignment: .top, spacing: gap) {
                ForEach(weeks.indices, id: \.self) { column in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            if let point = weeks[column][row] {
                                cell(point, busiest: busiest, side: side)
                            } else {
                                Color.clear.frame(width: side, height: side)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ point: DashboardSnapshot.Point, busiest: Int, side: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: max(1, side / 5))
        let label = HeatmapLabel.describe(point, unit: unit)
        Group {
            if let count = point.count {
                shape.fill(SlopPalette.fill(level: SlopPalette.level(count, max: busiest)))
            } else {
                shape.strokeBorder(SlopPalette.unknown, style: StrokeStyle(lineWidth: 1, dash: [2]))
            }
        }
        .overlay {
            if point.isIncomplete || selection?.wrappedValue == point.day {
                shape.strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            }
        }
        .frame(width: side, height: side)
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
