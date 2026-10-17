import SlopometerCore
import SwiftUI

/// Places in Settings the dashboard can send someone to.
enum SettingsAnchor: Hashable {
    case account
    case token
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.dashboard
    @State private var settingsFocus: SettingsAnchor?

    enum Tab { case dashboard, settings }

    var body: some View {
        TabView(selection: $tab) {
            DashboardView(openSettings: { anchor in
                settingsFocus = anchor
                tab = .settings
            })
            .tabItem { Label("Dashboard", systemImage: "chart.bar") }
            .tag(Tab.dashboard)
            SettingsView(focus: $settingsFocus)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(SlopPalette.mark)
        .padding()
        .frame(minWidth: 640, minHeight: 540)
        .onAppear { if model.settings.login.isEmpty { tab = .settings } }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedDay: CalendarDay?
    let openSettings: (SettingsAnchor) -> Void

    var body: some View {
        @Bindable var model = model
        let snapshot = model.snapshot
        let gated = snapshot.metric.requiresToken && !model.tokenUsable
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(snapshot)
                if snapshot.tier == .notConfigured {
                    ContentUnavailableView {
                        Label(
                            "No account yet", systemImage: "person.crop.circle.badge.questionmark")
                    } description: {
                        Text("Enter a GitHub username to measure its contribution calendar.")
                    } actions: {
                        Button("Add Username") { openSettings(.account) }
                    }
                } else {
                    if let quota = snapshot.quota { QuotaCard(quota: quota) }
                    controls($model.settings)
                    if gated {
                        TokenGate(metric: snapshot.metric) { openSettings(.token) }
                    } else {
                        SlopChart(
                            points: snapshot.points, style: snapshot.chartStyle,
                            unit: snapshot.unit, showsAverage: snapshot.averageWindow > 0,
                            selection: $selectedDay, gridMaxHeight: 220
                        )
                        .frame(height: snapshot.chartStyle == .grid ? nil : 220)
                        footnote(snapshot)
                        if let selectedDay { dayDetail(selectedDay, snapshot: snapshot) }
                    }
                    notices(snapshot, gated: gated)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    private func header(_ snapshot: DashboardSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Slopometer").font(.largeTitle.weight(.semibold))
                Text("Your daily slop, quantified.").foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if !snapshot.login.isEmpty {
                    HStack(spacing: 8) {
                        Text("@\(snapshot.login)").font(.callout.weight(.medium))
                        TierBadge(tier: snapshot.tier)
                    }
                }
                HStack(spacing: 6) {
                    freshness(snapshot).font(.caption).foregroundStyle(.secondary)
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
                        .accessibilityLabel("Refresh now")
                        .disabled(snapshot.login.isEmpty)
                    }
                }
            }
        }
    }

    private func controls(_ settings: Binding<DashboardSettings>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Metric", selection: settings.metric) {
                ForEach(Metric.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 16) {
                Picker("View", selection: settings.chartStyle) {
                    ForEach(ChartStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Its own width: a max-width frame narrower than the control centers it and
                // clips the first segment when the selected segment's label widens.
                .fixedSize()
                Spacer()
                Picker("Range", selection: settings.rangeDays) {
                    ForEach(DashboardSettings.ranges, id: \.self) { Text("\($0) days").tag($0) }
                }
                .fixedSize()
                Picker("Average", selection: settings.averageWindow) {
                    Text("Off").tag(0)
                    Text("7-day").tag(7)
                    Text("30-day").tag(30)
                }
                .fixedSize()
                .disabled(settings.wrappedValue.chartStyle == .grid)
                .help(
                    settings.wrappedValue.chartStyle == .grid
                        ? "Averages show in the column and line views." : "")
            }
            .disabled(model.snapshot.metric.requiresToken && !model.tokenUsable)
        }
    }

    /// Source and scope in one sentence, instead of a string of joined labels.
    private func footnote(_ snapshot: DashboardSnapshot) -> some View {
        var parts: [String] = []
        if let today = snapshot.todayCount {
            parts.append("\(today) \(snapshot.unit) so far today.")
        }
        let scope = snapshot.scopeLabel.isEmpty ? "" : ", \(snapshot.scopeLabel.lowercased())"
        parts.append("Source: \(snapshot.sourceLabel)\(scope).")
        return Text(parts.joined(separator: " "))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func dayDetail(_ day: CalendarDay, snapshot: DashboardSnapshot) -> some View {
        let point = snapshot.points.first { $0.day == day }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(
                    point.map { HeatmapLabel.describe($0, unit: snapshot.unit) } ?? day.description
                )
                .font(.headline)
                Spacer()
                Button {
                    selectedDay = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
                .accessibilityLabel("Close day details")
            }
            if snapshot.metric.requiresToken {
                let prs = model.evidence(on: day)
                if prs.isEmpty {
                    Text("No PRs counted on this day.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(prs) { PullRequestRow(record: $0) }
                    }
                }
            } else {
                Text("GitHub reports contributions as a daily total, without the items behind it.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func notices(_ snapshot: DashboardSnapshot, gated: Bool) -> some View {
        let tokenNotice = SnapshotBuilder.tokenNeededNotice(for: snapshot.metric)
        let shown =
            snapshot.notices.filter { !(gated && $0 == tokenNotice) }
            + [model.widgetProblem].compactMap { $0 }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown, id: \.self) { notice in
                    Label(notice, systemImage: "info.circle")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// Counts up from the last sync. SwiftUI redraws only this text, and only while the
    /// window is visible; nothing is polled or recomputed.
    private func freshness(_ snapshot: DashboardSnapshot) -> Text {
        guard let synced = snapshot.lastSuccessfulSync else { return Text("Not synced yet") }
        return Text("Synced \(synced, style: .relative) ago")
    }
}

/// Which access tier the numbers come from, so a missing token is visible at a glance.
private struct TierBadge: View {
    let tier: DashboardSnapshot.Tier

    var body: some View {
        let isToken = tier == .token
        Label(
            isToken ? "Token" : "Username only",
            systemImage: isToken ? "key.fill" : "person"
        )
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(isToken ? SlopPalette.mark : .secondary)
        .background(
            (isToken ? SlopPalette.mark : Color.secondary).opacity(0.14), in: Capsule())
    }
}

/// Shown in place of the chart when a PR metric is selected without a usable token.
private struct TokenGate: View {
    @Environment(AppModel.self) private var model
    let metric: Metric
    let openTokenSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(SlopPalette.mark)
            VStack(spacing: 6) {
                Text(title).font(.title3.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button(model.hasToken ? "Review Tokens" : "Add Token", action: openTokenSettings)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                if !model.hasToken {
                    Link("Create one on GitHub", destination: TokenGuide.creationURL)
                }
            }
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var title: String {
        switch model.lastReport?.pullRequestError {
        case .tokenOwnerMismatch: "Your token belongs to another account"
        case .unauthorized: "GitHub rejected your token"
        default: "\(metric.title) needs a GitHub token"
        }
    }

    private var message: String {
        switch model.lastReport?.pullRequestError {
        case .tokenOwnerMismatch(_, let actual):
            "A saved token is for @\(actual), not @\(model.settings.login). Replace it with a token created on @\(model.settings.login)."
        case .unauthorized:
            "It may have expired or been revoked. Create a new one and replace it in Settings."
        default:
            "A username alone only shows contributions. To count the PRs you open and merge, add a fine-grained GitHub token with read-only Pull requests access."
        }
    }
}

private struct QuotaCard: View {
    let quota: DashboardSnapshot.Quota
    @State private var showsEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Button {
                    showsEvidence.toggle()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(quota.count)")
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                        Text("/ \(quota.target)")
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                .buttonStyle(.plain)
                .help("Show the PRs counted today")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily slop quota").font(.headline)
                    Text("\(quota.unit.capitalizedFirst) today in \(quota.scopeLabel)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                status
            }
            QuotaMeter(count: quota.count, target: quota.target)
                .accessibilityLabel(quota.headline)
            Button {
                withAnimation(.snappy) { showsEvidence.toggle() }
            } label: {
                Label(
                    showsEvidence ? "Hide PRs" : evidenceTitle,
                    systemImage: showsEvidence ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.borderless)
            .font(.callout)
            if showsEvidence {
                if quota.evidence.isEmpty {
                    Text("No PRs counted yet today.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(quota.evidence) { item in
                            EvidenceRow(
                                repository: item.repository, number: item.number,
                                title: item.title, url: item.url, isDraft: item.isDraft)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var evidenceTitle: String {
        quota.count == 1 ? "Show the PR counted" : "Show the \(quota.count) PRs counted"
    }

    @ViewBuilder
    private var status: some View {
        if !quota.coverageComplete {
            Label("Coverage incomplete", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else if quota.isReached {
            Label("Target reached", systemImage: "checkmark.seal.fill")
                .foregroundStyle(SlopPalette.mark)
        } else {
            Label("\(quota.target - quota.count) to go", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PullRequestRow: View {
    let record: PullRequestRecord

    var body: some View {
        EvidenceRow(
            repository: record.repository, number: record.number, title: record.title,
            url: record.url, isDraft: record.isDraft)
    }
}

/// One counted PR: title first, then where it lives. Opens the PR on GitHub.
private struct EvidenceRow: View {
    let repository: String
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool

    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) { content }
                .buttonStyle(.plain)
                .help("Open on GitHub")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .foregroundStyle(SlopPalette.mark)
                .font(.callout)
            Text(title).lineLimit(1)
            if isDraft {
                Text("Draft").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(repository) #\(number)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// Shared wording and links for creating the optional token.
enum TokenGuide {
    static let creationURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
