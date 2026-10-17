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
        let snapshot = SharedSnapshot.read()
        // The app requests reloads when data changes. Entries only advance the sync age,
        // one per minute for the next hour, without rereading the snapshot.
        let dates = SyncAgeLabel.updates(
            synced: snapshot?.lastSuccessfulSync, from: Date(), count: 60)
        let entries = dates.map { SnapshotEntry(date: $0, snapshot: snapshot) }
        let reload = dates.last.map { max($0, Date().addingTimeInterval(30 * 60)) }
        completion(Timeline(entries: entries, policy: .after(reload ?? Date())))
    }
}

struct SlopometerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        WidgetContent(snapshot: entry.snapshot, size: size, now: entry.date)
            .widgetURL(URL(string: "slopometer://open"))
            .containerBackground(.fill.tertiary, for: .widget)
    }

    private var size: WidgetSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        default: .large
        }
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
            "Your daily slop, quantified. Set up each size in Slopometer's Widgets tab."
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
