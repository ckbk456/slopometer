import SlopometerCore
import SwiftUI

/// Places in Settings the dashboard can send someone to.
enum SettingsAnchor: Hashable {
    case account
    case token
    case appearance
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.dashboard
    @State private var settingsFocus: SettingsAnchor?

    enum Tab { case dashboard, widgets, settings }

    var body: some View {
        // A segmented control in the window toolbar rather than a TabView, whose tab strip
        // macOS 26 draws as a cramped glass capsule inside the content.
        Group {
            switch tab {
            case .dashboard:
                DashboardView(openSettings: { anchor in
                    settingsFocus = anchor
                    tab = .settings
                })
            case .widgets:
                WidgetsView()
            case .settings:
                SettingsView(focus: $settingsFocus)
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 540)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SectionPicker(
                    selection: $tab,
                    options: [
                        .init(value: .dashboard, title: "Activity"),
                        .init(value: .widgets, title: "Widgets"),
                        .init(value: .settings, title: "Settings"),
                    ]
                )
                // Toolbar size in both densities.
                .controlSize(.regular)
            }
            .hidesSharedGlassBackground()
        }
        .onAppear { if model.accountLogin.isEmpty && !model.hasToken { tab = .settings } }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.density) private var density
    @State private var selectedDay: CalendarDay?
    let openSettings: (SettingsAnchor) -> Void

    var body: some View {
        @Bindable var model = model
        let snapshot = model.snapshot
        let gated = snapshot.metric.requiresToken && !model.tokenUsable
        // The chart takes whatever height the window has left over (at least
        // `chartMinHeight`); content taller than the window scrolls as before.
        GeometryReader { viewport in
            ScrollView {
                FillingStack(
                    spacing: density.pick(20, 12),
                    height: viewport.size.height - Self.verticalPadding * 2
                ) {
                    content(snapshot, gated: gated, settings: $model.settings)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, Self.verticalPadding)
            }
        }
    }

    private static let verticalPadding: CGFloat = 8
    private static let chartMinHeight: CGFloat = 220

    @ViewBuilder
    private func content(
        _ snapshot: DashboardSnapshot, gated: Bool, settings: Binding<DashboardSettings>
    ) -> some View {
        header(snapshot)
        if snapshot.tier == .notConfigured {
            if model.hasToken {
                ContentUnavailableView {
                    Label("Checking your tokens", systemImage: "key.horizontal")
                } description: {
                    Text("The account comes from your tokens once GitHub confirms who owns them.")
                } actions: {
                    Button("Review Tokens") { openSettings(.token) }
                }
            } else {
                ContentUnavailableView {
                    Label(
                        "No account yet", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("Add a token, or enter a GitHub username to see its contributions.")
                } actions: {
                    Button("Add Username") { openSettings(.account) }
                }
            }
        } else {
            if let quota = snapshot.quota { QuotaCard(quota: quota) }
            controls(settings)
            if gated {
                TokenGate(metric: snapshot.metric) { openSettings(.token) }
            } else {
                SlopChart(
                    points: snapshot.points, style: snapshot.chartStyle,
                    unit: snapshot.unit, showsAverage: snapshot.averageWindow > 0,
                    selection: $selectedDay
                )
                .layoutValue(key: FillsHeight.self, value: Self.chartMinHeight)
                footnote(snapshot)
                if let selectedDay { dayDetail(selectedDay, snapshot: snapshot) }
            }
            notices(snapshot, gated: gated)
        }
    }

    private func header(_ snapshot: DashboardSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Slopometer").font(.largeTitle.weight(.semibold))
                Text("Your daily slop, quantified.").foregroundStyle(.secondary)
            }
            Spacer()
            GlassGroup(spacing: 4) {
                VStack(alignment: .trailing, spacing: 6) {
                    if !snapshot.login.isEmpty {
                        HStack(spacing: 8) {
                            Text("@\(snapshot.login)").font(.callout.weight(.medium))
                            ConnectionBadge { openSettings(.token) }
                        }
                    }
                    HStack(spacing: 6) {
                        freshness(snapshot).font(.caption).foregroundStyle(.secondary)
                        if model.isSyncing {
                            ProgressView().controlSize(.small)
                                .help(model.refreshLabel)
                                .accessibilityLabel(model.refreshLabel)
                        } else {
                            Button {
                                Task { await model.refresh() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .glassIconButtonStyle()
                            .help("Refresh now")
                            .accessibilityLabel("Refresh now")
                            .disabled(snapshot.login.isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func controls(_ settings: Binding<DashboardSettings>) -> some View {
        VStack(alignment: .leading, spacing: density.pick(12, 8)) {
            HStack(spacing: 12) {
                Picker("Metric", selection: settings.metric) {
                    ForEach(Metric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                ConfigurationMenu()
                    .fixedSize()
            }
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
                        ? "Averages show in columns and line." : "")
                Button("Colors", systemImage: "paintpalette") { openSettings(.appearance) }
                    .labelStyle(.iconOnly)
                    .help("Change colors and appearance in Settings")
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
                // Borderless, not glass: the card is already glass.
                .buttonStyle(.borderless)
                .help("Close")
                .accessibilityLabel("Close day details")
            }
            if snapshot.metric.requiresToken {
                let prs = model.evidence(on: day)
                if prs.isEmpty {
                    Text("No PRs counted this day.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(prs) { PullRequestRow(record: $0) }
                    }
                }
            } else {
                Text("GitHub gives contributions as a daily total only.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 10)
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

/// The connection in use (public profile, or which tokens), so a missing token is visible at
/// a glance. Clicking it lists every saved token and how it feeds the data; never secrets.
private struct ConnectionBadge: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slopColors) private var colors
    let manage: () -> Void
    @State private var isPresented = false

    var body: some View {
        let usesTokens = model.tokenUsable
        Button {
            isPresented.toggle()
        } label: {
            Label(model.connectionLabel, systemImage: usesTokens ? "key.fill" : "person")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(usesTokens ? colors.markText : .secondary)
                .glassCapsule(tint: usesTokens ? colors.mark : Color.secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show where the data comes from")
        .accessibilityLabel("Connection: \(model.connectionLabel)")
        .accessibilityHint("Shows the tokens feeding the data")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ConnectionDetails {
                isPresented = false
                manage()
            }
        }
    }
}

/// Every saved token with its kind, owner, and whether it is counted.
private struct ConnectionDetails: View {
    @Environment(AppModel.self) private var model
    let manage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.connectionLabel).font(.headline)
                Text(caption).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.tokens.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.tokens) { TokenSummaryRow(entry: $0) }
                }
            }
            HStack {
                Spacer()
                Button("Manage in Settings", action: manage)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }

    private var caption: String {
        let login = model.accountLogin
        if model.tokens.isEmpty {
            return
                "Contributions for @\(login) come from the public profile. Add a token to count PRs."
        }
        return login.isEmpty
            ? "Waiting for GitHub to confirm who owns your tokens."
            : "Tokens owned by @\(login) are counted. Values stay in Keychain."
    }
}

/// One saved token: name, kind, and its standing. Shared by Settings and the badge popover.
struct TokenSummaryRow<Trailing: View>: View {
    @Environment(AppModel.self) private var model
    let entry: TokenEntry
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let state = model.state(of: entry)
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon(state))
                .foregroundStyle(state.isProblem ? Color.orange : Color.secondary)
                .frame(width: 18)
                // The summary below says the same in words.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.label).lineLimit(1)
                    TokenKindChip(kind: entry.kind)
                }
                Text(state.summary)
                    .font(.caption)
                    .foregroundStyle(state.isProblem ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }

    private func icon(_ state: TokenState) -> String {
        switch state {
        case .checking: "hourglass"
        case .counted: "checkmark.circle.fill"
        case .otherOwner: "person.crop.circle.badge.xmark"
        case .rejected, .unavailable: "exclamationmark.triangle.fill"
        }
    }
}

extension TokenSummaryRow where Trailing == EmptyView {
    init(entry: TokenEntry) {
        self.init(entry: entry) { EmptyView() }
    }
}

/// Fine-grained or classic, in words; classic is tinted because it can write.
struct TokenKindChip: View {
    let kind: AccessToken.Kind

    var body: some View {
        let classic = kind == .classic
        Text(classic ? "Classic" : "Fine-grained")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(classic ? Color.orange : Color.secondary)
            .background(
                (classic ? Color.orange : Color.secondary).opacity(0.14), in: Capsule())
    }
}

/// Shown in place of the chart when a PR metric is selected without a usable token.
private struct TokenGate: View {
    @Environment(AppModel.self) private var model
    @Environment(\.slopColors) private var colors
    let metric: Metric
    let openTokenSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(colors.markText)
            VStack(spacing: 6) {
                Text(title).font(.title3.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                // Bordered, not glass: the card behind it is already glass.
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
        .glassCard(cornerRadius: 12)
    }

    private var states: [TokenState] { model.tokens.map { model.state(of: $0) } }

    private var title: String {
        if states.contains(.checking) { return "Checking your tokens" }
        if states.contains(.rejected) { return "GitHub rejected your token" }
        if states.contains(where: { $0.owner != nil }) {
            return "Your tokens belong to another account"
        }
        return "\(metric.title) needs a GitHub token"
    }

    private var message: String {
        if states.contains(.checking) {
            return "PR stats appear once GitHub confirms who owns them."
        }
        if states.contains(.rejected) {
            return "It may have expired or been revoked. Replace it in Settings."
        }
        if let owner = states.lazy.compactMap(\.owner).first {
            return "A saved token is for @\(owner), not @\(model.accountLogin)."
        }
        return
            "A username only shows contributions. To count PRs, add a fine-grained token with read-only Pull requests access."
    }
}

private struct QuotaCard: View {
    let quota: DashboardSnapshot.Quota
    @State private var showsEvidence = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.slopColors) private var colors

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
                withAnimation(reduceMotion ? nil : .snappy) { showsEvidence.toggle() }
            } label: {
                Label(
                    showsEvidence ? "Hide PRs" : evidenceTitle,
                    systemImage: showsEvidence ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.borderless)
            .font(.callout)
            if showsEvidence {
                if quota.evidence.isEmpty {
                    Text("No PRs yet today.").foregroundStyle(.secondary)
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
        .glassCard(cornerRadius: 12)
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
                .foregroundStyle(colors.markText)
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
    @Environment(\.slopColors) private var colors

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
                .foregroundStyle(colors.markText)
                .font(.callout)
                .accessibilityHidden(true)
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

/// Marks the one child of `FillingStack` that takes the leftover height, with its minimum.
private struct FillsHeight: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

/// A leading-aligned vertical stack for scroll content. Children get their ideal height,
/// except the one marked `FillsHeight`, which is offered whatever is left of `height`
/// (the visible height), but never less than its minimum. When the rest is taller than
/// the window, that child gets its minimum and the scroll view scrolls. `height` comes
/// from the scroll view's frame, not from the content, so resizing cannot feed back into
/// itself and jitter. A child may take less than it is offered (the grid stays square).
private struct FillingStack: Layout {
    let spacing: CGFloat
    let height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(width: proposal.width, subviews: subviews)
        let width = proposal.width ?? sizes.map(\.width).max() ?? 0
        return CGSize(width: width, height: total(sizes))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let sizes = measure(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (subview, size) in zip(subviews, sizes) {
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height + spacing
        }
    }

    private func measure(width: CGFloat?, subviews: Subviews) -> [CGSize] {
        var sizes = subviews.map { subview -> CGSize in
            subview[FillsHeight.self] == nil
                ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) : .zero
        }
        let fixed = total(sizes)
        for (index, subview) in subviews.enumerated() {
            guard let minimum = subview[FillsHeight.self] else { continue }
            let offered = max(minimum, height - fixed)
            sizes[index] = subview.sizeThatFits(ProposedViewSize(width: width, height: offered))
        }
        return sizes
    }

    private func total(_ sizes: [CGSize]) -> CGFloat {
        sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
    }
}

/// Shared wording and links for creating the optional token.
enum TokenGuide {
    static let creationURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!
    /// Where each kind of token is revoked; Slopometer can't revoke them itself.
    static let fineGrainedListURL = URL(
        string: "https://github.com/settings/personal-access-tokens")!
    static let classicListURL = URL(string: "https://github.com/settings/tokens")!
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
