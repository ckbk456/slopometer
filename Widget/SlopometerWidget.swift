import SlopometerCore
import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// Nil when the app has not shared a snapshot this widget can read.
    let snapshot: DashboardSnapshot?
}

/// Only decodes the snapshot the app publishes; never fetches or reads credentials.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: SharedSnapshot.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: SharedSnapshot.read())
        // The app requests reloads when data changes; this only refreshes the age label.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct SlopometerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.tier != .notConfigured {
                if snapshot.metric.requiresToken, snapshot.tier != .token, snapshot.quota == nil {
                    message(
                        "\(snapshot.metric.title) needs a GitHub token",
                        detail: "Add one in Slopometer's settings.")
                } else {
                    measured(snapshot)
                }
            } else if entry.snapshot == nil {
                message(
                    "No data yet", detail: "Open Slopometer to share your latest numbers here.")
            } else {
                message("Slopometer", detail: "Open the app and enter a GitHub username.")
            }
        }
        .widgetURL(URL(string: "slopometer://open"))
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.title3)
                .foregroundStyle(SlopPalette.mark)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text(title).font(.headline).lineLimit(2)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Each size shows a fixed window suited to its shape, labeled in the footer.
    @ViewBuilder
    private func measured(_ snapshot: DashboardSnapshot) -> some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                headline(snapshot)
                Spacer(minLength: 0)
                // A clock time keeps its width; a ticking relative age gets truncated here.
                Text("Synced \(syncTime(snapshot))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                compactHeadline(snapshot)
                Spacer(minLength: 0)
                WeekStrip(points: Array(snapshot.recentPoints.suffix(7)), unit: snapshot.unit)
                footer(snapshot, window: "Last 7 days")
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                headline(snapshot)
                largeChart(snapshot)
                footer(snapshot, window: largeWindowLabel(snapshot))
            }
        }
    }

    @ViewBuilder
    private func largeChart(_ snapshot: DashboardSnapshot) -> some View {
        let points = largePoints(snapshot)
        if points.isEmpty {
            Spacer(minLength: 0)
        } else {
            SlopChart(
                points: points, style: snapshot.chartStyle, unit: snapshot.unit,
                showsAverage: false, compact: true
            )
            .widgetAccentable()
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// Grid: always the last 26 weeks. Columns and line: up to 90 days of the app's range.
    private func largePoints(_ snapshot: DashboardSnapshot) -> [DashboardSnapshot.Point] {
        snapshot.chartStyle == .grid
            ? snapshot.recentPoints : Array(snapshot.points.suffix(Self.trendDays))
    }

    private static let trendDays = 90

    private func largeWindowLabel(_ snapshot: DashboardSnapshot) -> String {
        snapshot.chartStyle == .grid
            ? "Last \(SnapshotBuilder.recentDays / 7) weeks"
            : "Last \(min(Self.trendDays, snapshot.points.count)) days"
    }

    private func headline(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let quota = snapshot.quota {
                quotaCount(quota)
                QuotaMeter(count: quota.count, target: quota.target, height: 6)
                Text("\(quota.unit) today")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text(snapshot.todayCount.map(String.init) ?? "–")
                    .font(countFont)
                    .monospacedDigit()
                Text("\(snapshot.unit) today so far")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One row for the medium widget, leaving its height to the week strip.
    private func compactHeadline(_ snapshot: DashboardSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let quota = snapshot.quota {
                quotaCount(quota)
                VStack(alignment: .leading, spacing: 4) {
                    QuotaMeter(count: quota.count, target: quota.target, height: 5)
                    Text("\(quota.unit) today")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text(snapshot.todayCount.map(String.init) ?? "–")
                    .font(countFont)
                    .monospacedDigit()
                Text("\(snapshot.unit) today so far")
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
        .system(size: family == .systemSmall ? 36 : 30, weight: .semibold, design: .rounded)
    }

    /// Changing text on the left, the constant window label on the right, so the age's
    /// width never shifts anything. Names the chart's metric when it differs from the quota.
    private func footer(_ snapshot: DashboardSnapshot, window: String) -> some View {
        let label =
            snapshot.quota.map { $0.unit != snapshot.unit } == true
            ? "\(snapshot.metric.title), \(window.prefix(1).lowercased() + window.dropFirst())"
            : window
        return HStack(spacing: 8) {
            if let synced = snapshot.lastSuccessfulSync {
                Text("Synced \(synced, style: .relative) ago")
            } else {
                Text("Not synced yet")
            }
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
                    tile(point, busiest: busiest)
                    Text(point.day.start(in: .current), format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HeatmapLabel.describe(point, unit: unit))
            }
        }
    }

    private func tile(_ point: DashboardSnapshot.Point, busiest: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return ZStack {
            if let count = point.count {
                shape.fill(SlopPalette.fill(level: SlopPalette.level(count, max: busiest)))
                    .widgetAccentable()
                Text("\(count)")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            } else {
                shape.strokeBorder(SlopPalette.unknown, style: StrokeStyle(lineWidth: 1, dash: [2]))
                Text("–").font(.callout).foregroundStyle(.secondary)
            }
            if point.isIncomplete {
                shape.strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
    }
}

@main
struct SlopometerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SlopometerWidget", provider: SnapshotProvider()) { entry in
            SlopometerWidgetView(entry: entry)
        }
        .configurationDisplayName("Slopometer")
        .description(
            "Your daily slop, quantified: today's count or PR quota, with the last week or months."
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
