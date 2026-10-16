import SlopometerCore
import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: DashboardSnapshot
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
        let entry = SnapshotEntry(date: Date(), snapshot: SharedSnapshot.read() ?? .placeholder)
        // The app requests reloads when data changes; this only refreshes the age label.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct SlopometerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snapshot: DashboardSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headline
            if family != .systemSmall, !snapshot.points.isEmpty {
                SlopChart(
                    points: visiblePoints, style: snapshot.chartStyle, unit: snapshot.unit,
                    showsAverage: snapshot.averageWindow > 0, compact: true)
            }
            Spacer(minLength: 0)
            footer
        }
        .widgetURL(URL(string: "slopometer://open"))
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let quota = snapshot.quota {
                Text("\(quota.count) / \(quota.target)")
                    .font(
                        .system(
                            size: family == .systemSmall ? 34 : 28, weight: .semibold,
                            design: .rounded)
                    )
                    .monospacedDigit()
                Text("Daily slop quota · \(quota.unit)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else if snapshot.tier == .notConfigured {
                Text("Slopometer").font(.headline)
                Text("Open the app and enter a GitHub username.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(snapshot.todayCount.map(String.init) ?? "–")
                    .font(
                        .system(
                            size: family == .systemSmall ? 34 : 28, weight: .semibold,
                            design: .rounded)
                    )
                    .monospacedDigit()
                Text("\(snapshot.unit) today so far")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        Group {
            if let synced = snapshot.lastSuccessfulSync {
                Text("Synced \(synced, style: .relative) ago")
            } else if snapshot.tier != .notConfigured {
                Text("Not synced yet")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    /// The widget shows the most recent days that fit its size.
    private var visiblePoints: [DashboardSnapshot.Point] {
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
