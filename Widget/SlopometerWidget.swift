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
        WidgetContent(snapshot: entry.snapshot, size: size)
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
            "Your daily slop, quantified. Choose what each size shows in Slopometer's Settings."
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
