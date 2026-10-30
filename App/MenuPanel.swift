import AppKit
import SlopometerCore
import SwiftUI

/// The menu bar panel: today's headline count, the quota meter, the last seven days, and
/// sync status, readable at a glance. Settings and inspection stay in the app window.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater
    @Environment(\.dismiss) private var dismiss
    @Environment(\.slopColors) private var colors
    @Environment(\.density) private var density

    private var snapshot: DashboardSnapshot { model.snapshot }
    private var metric: Metric { model.menuBarMetric }
    private var needsLogin: Bool { model.accountLogin.isEmpty }
    /// A PR metric without a usable token: there is no count to show, only the reason.
    private var needsToken: Bool {
        !needsLogin && snapshot.quota == nil && metric.requiresToken && !model.tokenUsable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .padding(density.pick(20, 14))
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                syncRow
                if !snapshot.login.isEmpty { accountRow }
                if !needsLogin, !model.settings.savedConfigurations.isEmpty { configurationRow }
                ForEach(notices, id: \.self) { notice in
                    PanelRow(
                        icon: "exclamationmark.triangle.fill", iconStyle: colors.warning,
                        title: notice)
                }
                if let version = updater.pendingVersion { updateRow(version) }
            }
            .padding(6)
            Divider()
            footer
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .frame(width: density.pick(300, 280))
        .background { PanelBacking() }
        .overlay {
            if snapshot.quota?.achievement != nil {
                QuotaAchievementBorder(cornerRadius: 12)
            }
        }
    }

    // MARK: Headline

    @ViewBuilder
    private var hero: some View {
        if needsLogin {
            VStack(alignment: .leading, spacing: 10) {
                caption("Slopometer", systemImage: "person.crop.circle.badge.questionmark")
                Text("Set up your account")
                    .font(.title2.weight(.semibold))
                Text("Open Slopometer and enter a GitHub username.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    openMainWindow()
                } label: {
                    Label("Open Slopometer", systemImage: "macwindow")
                }
                .modifier(PanelButtonStyle(prominent: true))
            }
            .accessibilityElement(children: .contain)
        } else if let quota = snapshot.quota {
            quotaHero(quota)
        } else {
            countHero
        }
    }

    private func quotaHero(_ quota: DashboardSnapshot.Quota) -> some View {
        VStack(alignment: .leading, spacing: density.pick(14, 10)) {
            VStack(alignment: .leading, spacing: 6) {
                metricCaption("Daily slop quota")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(quota.count)")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text("/ \(quota.target)")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                Text("\(quota.unit.capitalizedFirst) today · \(quota.scopeLabel)")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                quotaStatus(quota)
                    .padding(.top, 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(quota.headline)
            .accessibilityValue(statusText(quota))
            if let achievement = quota.achievement {
                QuotaAchievementLabel(achievement: achievement)
            }
            QuotaMeter(count: quota.count, target: quota.target)
                .accessibilityLabel("Quota progress")
                .accessibilityValue("\(quota.count) of \(quota.target) \(quota.unit)")
            if let week { WeekRow(points: week, unit: metric.unit) }
        }
    }

    private var countHero: some View {
        VStack(alignment: .leading, spacing: density.pick(14, 10)) {
            VStack(alignment: .leading, spacing: 6) {
                metricCaption(metric.title)
                Text(snapshot.todayCount.map(String.init) ?? "–")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(countDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.menuBarDescription)
            .accessibilityValue(needsToken ? countDetail : "")
            if let week { WeekRow(points: week, unit: metric.unit) }
        }
    }

    private var countDetail: String {
        if needsToken { return "\(metric.title) needs a GitHub token. Add one in Slopometer." }
        if snapshot.todayCount != nil { return "\(metric.unit.capitalizedFirst) today so far" }
        return "No count for today yet"
    }

    @ViewBuilder
    private func quotaStatus(_ quota: DashboardSnapshot.Quota) -> some View {
        if !quota.coverageComplete {
            Label(statusText(quota), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(colors.warning)
        } else if quota.isReached {
            Label(statusText(quota), systemImage: "checkmark.seal.fill")
                .foregroundStyle(colors.achievementText)
        } else {
            Label {
                Text(statusText(quota))
            } icon: {
                OcticonImage(metric: metric)
            }
        }
    }

    /// The same wording as the dashboard's quota card.
    private func statusText(_ quota: DashboardSnapshot.Quota) -> String {
        if !quota.coverageComplete { return "Coverage incomplete" }
        if quota.isReached { return "Target reached" }
        return "\(quota.target - quota.count) to go"
    }

    private func metricCaption(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(Self.iconName(for: metric))
                .renderingMode(.template)
                .resizable()
                .frame(width: 12, height: 12)
            Text(title.uppercased())
        }
        .font(.caption.weight(.semibold))
        .tracking(1)
        .foregroundStyle(.secondary)
    }

    private func caption(_ title: String, systemImage: String) -> some View {
        Label(title.uppercased(), systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .tracking(1)
            .foregroundStyle(.secondary)
    }

    /// The last seven days of the displayed metric, taken from series the snapshot already
    /// holds (the dashboard's or a widget's). Hidden when no series matches or all are unknown.
    private var week: [DashboardSnapshot.Point]? {
        let series =
            (snapshot.metric == metric ? [snapshot.points] : [])
            + snapshot.widgets.filter { $0.metric == metric }.map(\.points)
        guard let points = series.first(where: { $0.count >= 7 }) else { return nil }
        let week = Array(points.suffix(7))
        return week.contains { $0.count != nil } ? week : nil
    }

    static func iconName(for metric: Metric) -> String {
        switch metric {
        case .contributions: "octicon-calendar"
        case .prsOpened: "octicon-git-pull-request"
        case .prsMerged: "octicon-git-merge"
        }
    }

    // MARK: Status rows

    @ViewBuilder
    private var syncRow: some View {
        if model.isSyncing {
            PanelRow(
                icon: "arrow.triangle.2.circlepath",
                title: model.syncStage?.label ?? "Syncing with GitHub…")
        } else if let synced = snapshot.lastSuccessfulSync {
            PanelRow(icon: "arrow.triangle.2.circlepath", title: "Synced") {
                Text("\(synced, style: .relative) ago")
            }
            .help("Last synced \(synced.formatted(date: .abbreviated, time: .shortened))")
        } else {
            PanelRow(icon: "arrow.triangle.2.circlepath", title: "Not synced yet")
        }
    }

    /// The account and the connection in use, worded as in the app window's badge.
    private var accountRow: some View {
        let isToken = model.tokenUsable
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("@\(snapshot.login)")
                Label(model.connectionLabel, systemImage: isToken ? "key.fill" : "person")
                    .font(.caption)
                    .foregroundStyle(
                        isToken ? AnyShapeStyle(colors.markText) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, density.pick(5, 3))
        .accessibilityElement(children: .combine)
    }

    /// Shown after a scheduled check finds a release, until its alert is looked at.
    private func updateRow(_ version: String) -> some View {
        Button {
            dismiss()
            updater.checkForUpdates()
        } label: {
            PanelRow(
                icon: "arrow.down.circle.fill", iconStyle: colors.markText,
                title: "Slopometer \(version) is available"
            ) {
                Text("View")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show the update")
        .accessibilityLabel("Slopometer \(version) is available. Show the update.")
    }

    /// Switches saved configurations; saving and editing them happens in the app window.
    private var configurationRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            ConfigurationMenu(manages: false)
                .menuStyle(.borderlessButton)
                .labelStyle(.titleOnly)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, density.pick(5, 3))
    }

    /// Snapshot notices the headline does not already explain, plus widget sharing problems.
    private var notices: [String] {
        guard !needsLogin else { return [] }
        let tokenNotice = SnapshotBuilder.tokenNeededNotice(for: snapshot.metric)
        return snapshot.notices.filter { !(needsToken && $0 == tokenNotice) }
            + [model.widgetProblem].compactMap { $0 }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    if model.isSyncing {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Refresh")
                        }
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isSyncing || needsLogin)
                .keyboardShortcut("r")
                .help("Refresh now (⌘R)")
                .accessibilityLabel(model.isSyncing ? model.refreshLabel : "Refresh now")

                Button {
                    openMainWindow()
                } label: {
                    Label("Open", systemImage: "macwindow")
                }
                .keyboardShortcut("o")
                .help("Open Slopometer (⌘O)")
                .accessibilityLabel("Open Slopometer")

                Spacer(minLength: 0)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .keyboardShortcut("q")
                .help("Quit Slopometer (⌘Q)")
                .accessibilityLabel("Quit Slopometer")
            }
            .modifier(PanelButtonStyle(prominent: false))

            Text("Version \(BuildInfo.summary)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(
                    BuildInfo.commit.hasSuffix("-modified")
                        ? AnyShapeStyle(colors.warning) : AnyShapeStyle(.tertiary)
                )
                .textSelection(.enabled)
                .help("Slopometer version, build number, and source commit")
        }
    }

    /// Closes the panel first so the window comes forward on its own.
    private func openMainWindow() {
        dismiss()
        model.openMainWindow()
    }
}

/// macOS 26 and later draw the panel in the system's Liquid Glass, as Apple's own menu bar
/// extras are, so nothing is laid over it; the system adapts it for Reduce Transparency.
/// Earlier systems, and builds from SDKs before macOS 26, get the older vibrant material,
/// which lets a busy wallpaper wash out theme colors, so a mostly opaque window background
/// sits behind the content there.
private struct PanelBacking: View {
    var body: some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                Color.clear
            } else {
                fallback
            }
        #else
            fallback
        #endif
    }

    private var fallback: some View {
        Color(nsColor: .windowBackgroundColor).opacity(0.82).ignoresSafeArea()
    }
}

/// One icon-led status line. The title stays in the primary color so it reads on the
/// translucent panel; an optional trailing value is secondary unless styled.
private struct PanelRow<Value: View>: View {
    @Environment(\.density) private var density
    let icon: String
    let iconStyle: Color?
    let title: String
    let value: Value
    let valueStyle: AnyShapeStyle

    init(
        icon: String, iconStyle: Color? = nil, title: String,
        @ViewBuilder value: () -> Value,
        valueStyle: () -> AnyShapeStyle = { AnyShapeStyle(.secondary) }
    ) {
        self.icon = icon
        self.iconStyle = iconStyle
        self.title = title
        self.value = value()
        self.valueStyle = valueStyle()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconStyle.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .frame(width: 18)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            value
                .foregroundStyle(valueStyle)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, density.pick(5, 3))
        .accessibilityElement(children: .combine)
    }
}

extension PanelRow where Value == EmptyView {
    init(icon: String, iconStyle: Color? = nil, title: String) {
        self.init(icon: icon, iconStyle: iconStyle, title: title) { EmptyView() }
    }
}

/// Seven labeled day tiles with their counts, so the week reads without relying on color.
/// Unknown days show an en dash; today is outlined because it is still in progress.
private struct WeekRow: View {
    let points: [DashboardSnapshot.Point]
    let unit: String

    var body: some View {
        let busiest = points.compactMap(\.count).max() ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(points) { point in
                    VStack(spacing: 3) {
                        DayTile(point: point, busiest: busiest, unit: unit)
                            .frame(height: 28)
                        Text(
                            point.day.start(in: .current),
                            format: .dateTime.weekday(.abbreviated)
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(HeatmapLabel.describe(point, unit: unit))
                }
            }
        }
    }
}

/// Liquid Glass buttons on macOS 26 and later; bordered buttons before. The compiler check
/// keeps the project building with SDKs that predate the glass styles (CI uses Xcode 16.4).
private struct PanelButtonStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                if prominent {
                    content.buttonStyle(.glassProminent)
                } else {
                    content.buttonStyle(.glass)
                }
            } else {
                fallback(content)
            }
        #else
            fallback(content)
        #endif
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// A metric's Octicon sized to sit beside text like an SF Symbol in a `Label`.
struct OcticonImage: View {
    let metric: Metric
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 13

    var body: some View {
        Image(MenuPanel.iconName(for: metric))
            .renderingMode(.template)
            .resizable()
            .frame(width: side, height: side)
    }
}
