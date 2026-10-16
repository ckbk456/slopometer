import SlopometerCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.dashboard

    enum Tab { case dashboard, settings }

    var body: some View {
        TabView(selection: $tab) {
            DashboardView(openSettings: { tab = .settings })
                .tabItem { Label("Dashboard", systemImage: "chart.bar") }
                .tag(Tab.dashboard)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .padding()
        .frame(minWidth: 640, minHeight: 540)
        .onAppear { if model.settings.login.isEmpty { tab = .settings } }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedDay: CalendarDay?
    let openSettings: () -> Void

    var body: some View {
        @Bindable var model = model
        let snapshot = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(snapshot)
                if snapshot.tier == .notConfigured {
                    ContentUnavailableView {
                        Label(
                            "No account yet", systemImage: "person.crop.circle.badge.questionmark")
                    } description: {
                        Text("Enter a GitHub username to measure its contribution calendar.")
                    } actions: {
                        Button("Open Settings", action: openSettings)
                    }
                } else {
                    if let quota = snapshot.quota { QuotaCard(quota: quota) }
                    controls($model.settings)
                    SlopChart(
                        points: snapshot.points, style: snapshot.chartStyle, unit: snapshot.unit,
                        showsAverage: snapshot.averageWindow > 0, selection: $selectedDay
                    )
                    .frame(height: 200)
                    legend(snapshot)
                    if let selectedDay { dayDetail(selectedDay, snapshot: snapshot) }
                    notices(snapshot)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func header(_ snapshot: DashboardSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Slopometer").font(.largeTitle.weight(.semibold))
                Text("Your daily slop, quantified.").foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if !snapshot.login.isEmpty {
                    Text(
                        "@\(snapshot.login) · \(snapshot.tier == .token ? "Token" : "Username only")"
                    )
                    .font(.callout.weight(.medium))
                }
                HStack(spacing: 6) {
                    Text(freshness(snapshot)).font(.caption).foregroundStyle(.secondary)
                    if model.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh now")
                        .disabled(snapshot.login.isEmpty)
                    }
                }
            }
        }
    }

    private func controls(_ settings: Binding<DashboardSettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Metric", selection: settings.metric) {
                ForEach(Metric.allCases) { metric in
                    Text(
                        metric.title
                            + (metric.requiresToken && !model.tokenUsable ? " (token)" : "")
                    )
                    .tag(metric)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 16) {
                Picker("View", selection: settings.chartStyle) {
                    ForEach(ChartStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                Picker("Range", selection: settings.rangeDays) {
                    ForEach(DashboardSettings.ranges, id: \.self) { Text("\($0) days").tag($0) }
                }
                .frame(maxWidth: 150)
                Picker("Average", selection: settings.averageWindow) {
                    Text("Off").tag(0)
                    Text("7-day").tag(7)
                    Text("30-day").tag(30)
                }
                .frame(maxWidth: 150)
                .disabled(settings.wrappedValue.chartStyle == .grid)
            }
        }
    }

    private func legend(_ snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 12) {
            Text("\(snapshot.metric.title) · \(snapshot.scopeLabel) · \(snapshot.sourceLabel)")
            if let today = snapshot.todayCount {
                Text("Today so far: \(today)")
            }
            if snapshot.averageWindow > 0, snapshot.chartStyle != .grid {
                Label("\(snapshot.averageWindow)-day average", systemImage: "line.diagonal")
                    .foregroundStyle(SlopPalette.average)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func dayDetail(_ day: CalendarDay, snapshot: DashboardSnapshot) -> some View {
        let point = snapshot.points.first { $0.day == day }
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    point.map { HeatmapLabel.describe($0, unit: snapshot.unit) } ?? day.description
                )
                .font(.headline)
                if snapshot.metric.requiresToken {
                    let prs = model.evidence(on: day)
                    if prs.isEmpty {
                        Text("No PRs counted on this day.").foregroundStyle(.secondary)
                    }
                    ForEach(prs) { PullRequestRow(record: $0) }
                } else {
                    Text("GitHub supplies contributions as a daily total without item details.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func notices(_ snapshot: DashboardSnapshot) -> some View {
        if !snapshot.notices.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(snapshot.notices, id: \.self) { notice in
                    Label(notice, systemImage: "info.circle")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func freshness(_ snapshot: DashboardSnapshot) -> String {
        guard let synced = snapshot.lastSuccessfulSync else { return "Not synced yet" }
        return "Synced \(synced.formatted(.relative(presentation: .named)))"
    }
}

private struct QuotaCard: View {
    let quota: DashboardSnapshot.Quota
    @State private var showsEvidence = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Button {
                        showsEvidence.toggle()
                    } label: {
                        Text("\(quota.count) / \(quota.target)")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .buttonStyle(.plain)
                    .help("Show the PRs counted today")
                    VStack(alignment: .leading) {
                        Text("Daily slop quota · \(quota.unit)").font(.headline)
                        Text("Today in \(quota.scopeLabel)").font(.caption).foregroundStyle(
                            .secondary)
                    }
                    Spacer()
                    status
                }
                ProgressView(
                    value: Double(min(quota.count, quota.target)), total: Double(quota.target)
                )
                .accessibilityLabel(quota.headline)
                if showsEvidence {
                    if quota.evidence.isEmpty {
                        Text("No PRs counted yet today.").foregroundStyle(.secondary)
                    }
                    ForEach(quota.evidence) { item in
                        Link(destination: URL(string: item.url)!) {
                            Text(
                                "\(item.repository)#\(item.number) \(item.title)\(item.isDraft ? " (draft)" : "")"
                            )
                            .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if !quota.coverageComplete {
            Label("Coverage incomplete", systemImage: "exclamationmark.triangle")
        } else if quota.isReached {
            Label("Target reached", systemImage: "checkmark.seal")
        } else {
            Label("\(quota.target - quota.count) to go", systemImage: "hourglass")
        }
    }
}

private struct PullRequestRow: View {
    let record: PullRequestRecord

    var body: some View {
        Link(destination: URL(string: record.url)!) {
            HStack {
                Text("\(record.repository)#\(record.number)").monospacedDigit()
                Text(record.title).lineLimit(1)
                if record.isDraft { Text("Draft").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
