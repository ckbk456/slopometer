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

    /// Opens the app that shipped this widget: `slopometer://` for releases,
    /// `slopometer-dev://` for Debug builds.
    private static let openURL = URL(
        string: (Bundle.main.object(forInfoDictionaryKey: "SlopometerURLScheme") as? String
            ?? "slopometer") + "://open")

    var body: some View {
        // The app shares its theme in the snapshot; older snapshots fall back to the standard.
        let content = WidgetContent(snapshot: entry.snapshot, size: size, now: entry.date)
            .slopTheme((entry.snapshot?.theme ?? .standard).resolved())
            .widgetURL(Self.openURL)
        if let scheme = forcedScheme {
            // The environment sits above slopTheme, so the theme resolves for the forced
            // scheme, and the background matches it instead of the desktop's.
            content
                .environment(\.colorScheme, scheme)
                .containerBackground(
                    Color(scheme == .dark ? SlopTheme.darkBackground : SlopTheme.lightBackground),
                    for: .widget)
        } else {
            content.containerBackground(.fill.tertiary, for: .widget)
        }
    }

    /// Nil follows the system, including for snapshots from before appearance modes.
    private var forcedScheme: ColorScheme? {
        switch entry.snapshot?.appearance {
        case .light: .light
        case .dark: .dark
        case .system, nil: nil
        }
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
