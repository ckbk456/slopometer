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
        .tint(SlopPalette.mark)
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.title3)
                .foregroundStyle(SlopPalette.mark)
            Spacer(minLength: 0)
            Text(title).font(.headline).lineLimit(2)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func measured(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headline(snapshot)
            if family != .systemSmall, !snapshot.points.isEmpty {
                SlopChart(
                    points: visiblePoints(snapshot), style: snapshot.chartStyle,
                    unit: snapshot.unit, showsAverage: snapshot.averageWindow > 0, compact: true)
            } else {
                Spacer(minLength: 0)
            }
            footer(snapshot)
        }
    }

    private func headline(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let quota = snapshot.quota {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(quota.count)").font(countFont)
                    Text("/ \(quota.target)")
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
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

    private var countFont: Font {
        .system(size: family == .systemSmall ? 36 : 30, weight: .semibold, design: .rounded)
    }

    private func footer(_ snapshot: DashboardSnapshot) -> some View {
        HStack {
            if family != .systemSmall, !snapshot.points.isEmpty {
                Text(windowLabel(snapshot))
            }
            Spacer(minLength: 4)
            if let synced = snapshot.lastSuccessfulSync {
                Text("Synced \(synced, style: .relative) ago")
            } else {
                Text("Not synced yet")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// Says how much of the selected range fits, since the widget may show only part of it.
    private func windowLabel(_ snapshot: DashboardSnapshot) -> String {
        let days = visiblePoints(snapshot).count
        return snapshot.chartStyle == .grid
            ? "Last \(Int((Double(days) / 7).rounded(.up))) weeks" : "Last \(days) days"
    }

    /// The widget shows the most recent days that fit its size.
    private func visiblePoints(_ snapshot: DashboardSnapshot) -> [DashboardSnapshot.Point] {
        let limit: Int
        switch (family, snapshot.chartStyle) {
        case (.systemMedium, .grid): limit = 7 * 20
        case (.systemMedium, _): limit = 30
        case (_, .grid): limit = 7 * 26
        default: limit = 90
        }
        return Array(snapshot.points.suffix(limit))
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
            "Your daily slop, quantified: today's count or PR quota, with the recent trend."
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
