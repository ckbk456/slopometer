import SlopometerCore
import SwiftUI

/// Per-size widget settings, each beside a live preview of what that size shows.
struct WidgetsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Text(
                    "Each widget size has its own settings; none follows the Activity tab's metric or view. Add widgets from Edit Widgets on the desktop or in Notification Center."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            sizeSection(
                .small, settings: $model.settings,
                summary: "The headline and the last sync time. No chart.")
            sizeSection(
                .medium, settings: $model.settings,
                summary: "A one-line headline and the last 7 days as daily tiles.")
            sizeSection(
                .large, settings: $model.settings,
                summary: "The headline and a chart with its own view and window.")
        }
        .formStyle(.grouped)
    }

    private func sizeSection(
        _ size: WidgetSize, settings: Binding<DashboardSettings>, summary: String
    ) -> some View {
        let panel = settings.widgets[size]
        return Section {
            WidgetPreview(snapshot: model.snapshot, size: size)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            Picker("Headline", selection: panel.headline) {
                ForEach(WidgetHeadline.allCases) { Text($0.title).tag($0) }
            }
            if panel.wrappedValue.headline == .quota, model.snapshot.quota == nil {
                Text(
                    "No daily PR quota is active, so this size shows today's count instead. Turn one on in Settings → Pull requests."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Picker(size == .small ? "Count" : "Metric", selection: panel.metric) {
                ForEach(Metric.allCases) { Text($0.title).tag($0) }
            }
            if size == .small {
                Text("Shown when the headline is today's count.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if panel.wrappedValue.metric.requiresToken, !model.tokenUsable {
                Text(
                    "\(panel.wrappedValue.metric.title) needs a GitHub token. Until then this size asks for one."
                )
                .font(.caption).foregroundStyle(.orange)
            }
            switch size {
            case .small:
                EmptyView()
            case .medium:
                LabeledContent("Window", value: "Last \(WidgetSettings.stripDays) days")
            case .large:
                Picker("View", selection: panel.chartStyle) {
                    ForEach(ChartStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if panel.wrappedValue.chartStyle == .grid {
                    LabeledContent("Window", value: "Last \(WidgetSettings.gridDays / 7) weeks")
                } else {
                    Picker("Window", selection: panel.windowDays) {
                        ForEach(WidgetSettings.windows, id: \.self) {
                            Text("Last \($0) days").tag($0)
                        }
                    }
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(size.title) widget")
                Text(summary)
                    .font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
            }
        }
    }
}

/// The widget's own content at the macOS point size of its family. Approximates the
/// desktop's material and margins; the system renders the real background and tint.
private struct WidgetPreview: View {
    let snapshot: DashboardSnapshot
    let size: WidgetSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        TimelineView(.everyMinute) { context in
            WidgetContent(snapshot: snapshot, size: size, now: context.date)
        }
        .padding(16)
        .frame(width: dimensions.width, height: dimensions.height)
        .background(.fill.tertiary, in: shape)
        .overlay(shape.strokeBorder(.separator))
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of the \(size.rawValue) widget")
    }

    private var dimensions: CGSize {
        switch size {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }
}
