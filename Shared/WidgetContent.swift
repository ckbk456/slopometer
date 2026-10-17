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

    var body: some View {
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
                .foregroundStyle(SlopPalette.mark)
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
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let busiest = points.compactMap(\.count).max() ?? 0
        HStack(spacing: 5) {
            ForEach(points) { point in
                VStack(spacing: 3) {
                    tile(point, busiest: busiest)
                    // Today is also named in bold: its outline vanishes on a bright tile
                    // when the desktop draws the widget in one color.
                    Text(point.day.start(in: .current), format: .dateTime.weekday(.abbreviated))
                        .font(.caption2.weight(point.isIncomplete ? .bold : .regular))
                        .foregroundStyle(point.isIncomplete ? .primary : .secondary)
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
                let level = SlopPalette.level(count, max: busiest)
                let fill = shape.fill(SlopPalette.fill(level: level))
                let label = Text("\(count)")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                if renderingMode != .fullColor, level >= 3 {
                    // Unfocused desktop widgets draw text and bright tiles in the same
                    // near-white, so the busiest days cut their number out of the tile.
                    fill.overlay { label.blendMode(.destinationOut) }
                        .compositingGroup()
                        .widgetAccentable()
                } else {
                    fill.widgetAccentable()
                    label
                }
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
