import AppKit
import SlopometerCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Binding var focus: SettingsAnchor?
    @FocusState private var focusedField: SettingsAnchor?
    @State private var login = ""
    @State private var addsToken = false

    var body: some View {
        @Bindable var model = model
        ScrollViewReader { proxy in
            form(bindable: $model)
                .onAppear { reveal(focus, with: proxy) }
                .onChange(of: focus) { _, anchor in reveal(anchor, with: proxy) }
        }
        .onAppear {
            login = model.settings.login
        }
        .sheet(isPresented: $addsToken) { AddTokenSheet().environment(model) }
    }

    private func form(bindable: Bindable<AppModel>) -> some View {
        Form {
            // Who is measured first: the account and how it is connected, then its tokens.
            Section {
                accountSummary
                HStack {
                    TextField("Username", text: $login, prompt: Text("Enter username"))
                        .focused($focusedField, equals: .account)
                        .onSubmit(applyLogin)
                    if !model.hasToken {
                        Button("Save", action: applyLogin)
                            .disabled(
                                login == model.settings.login || !GitHubClient.isValidLogin(login))
                    }
                }
                .disabled(model.hasToken)
                .id(SettingsAnchor.account)
                HStack(alignment: .firstTextBaseline) {
                    Text(usernameCaption)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    InfoButton("About the public profile") {
                        Text(
                            "Without a token, Slopometer reads the contribution calendar on the public GitHub profile. That page is not an official API, so it can change or break."
                        )
                        Text(
                            "Private activity appears only as anonymous counts, and only if the profile shows private contributions."
                        )
                        Text(
                            "With tokens, the account is the tokens' owner and this username is kept for when you remove them."
                        )
                    }
                }
            } header: {
                sectionHeader(
                    "Username",
                    caption: model.hasToken
                        ? "Not needed while tokens are saved."
                        : "Public profile only. Nothing secret is stored.")
            }

            Section {
                if model.tokens.isEmpty {
                    Text("No tokens yet. Contributions come from the public profile.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.tokens) { entry in
                    TokenSummaryRow(entry: entry) {
                        Button("Remove", role: .destructive) { model.removeToken(entry.id) }
                    }
                }
                HStack(spacing: 12) {
                    Button("Add Token…", action: presentAddToken)
                    Link(
                        "Create a fine-grained token on GitHub", destination: TokenGuide.creationURL
                    )
                    .font(.callout)
                    Spacer()
                    InfoButton("About tokens") {
                        Text("Create the token with:").fontWeight(.semibold)
                        Text(
                            """
                            Resource owner: your account, or an organization
                            Repository access: All repositories
                            Permissions: Pull requests, read-only (Metadata is added automatically)
                            """
                        )
                        Text("Organizations").fontWeight(.semibold)
                        Text(
                            "A token owned by your account can't see an organization's private repositories. To count those PRs, add another token with the organization as its resource owner. The organization may need to approve it."
                        )
                        Text("Account").fontWeight(.semibold)
                        Text(
                            "The account is whoever owns your tokens. Organization tokens are still owned by you, so they count. A token owned by someone else is kept but not counted."
                        )
                        Text("Tokens are stored in Keychain and only sent to GitHub.")
                            .foregroundStyle(.secondary)
                    }
                }
                .id(SettingsAnchor.token)
                insecuSlopometer(bindable)
            } header: {
                sectionHeader(
                    "Tokens",
                    caption:
                        "Read-only fine-grained tokens unlock PR stats, the daily quota, and repository filters."
                )
            }

            Section {
                LabeledContent("Repositories") {
                    RepositoryPicker(
                        selection: bindable.settings.repositories,
                        choices: RepositoryFilter.choices(
                            records: model.records, selected: model.settings.repositories))
                }
                Toggle("Daily PR quota", isOn: goalEnabled(bindable.settings))
                Group {
                    let goal = model.settings.goal ?? model.parkedGoal
                    Picker("Counts", selection: goalBinding(bindable.settings, \.metric, goal)) {
                        Text(Metric.prsMerged.unit).tag(Metric.prsMerged)
                        Text(Metric.prsOpened.unit).tag(Metric.prsOpened)
                    }
                    LabeledContent("Daily target") {
                        HStack(spacing: 6) {
                            TextField(
                                "Daily target", value: targetBinding(bindable.settings, goal),
                                format: .number.grouping(.never)
                            )
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                            Stepper(
                                "Daily target", value: targetBinding(bindable.settings, goal),
                                in: Goal.targetRange
                            )
                            .labelsHidden()
                            Text(goal.metric.unit).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(model.settings.goal == nil)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pull requests")
                    if !model.hasToken {
                        Text("Needs a token above.")
                            .font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!model.hasToken)

            Section("Timezone") {
                Picker("Timezone", selection: bindable.settings.timeZoneID) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("PR days and the quota reset at midnight here.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    InfoButton("About timezones") {
                        Text(
                            "PRs are counted by the calendar day they were opened or merged in this timezone, including daylight-saving changes."
                        )
                        Text(
                            "Contribution days keep GitHub's own day labels, so they can differ from this timezone by a day."
                        )
                    }
                }
            }

            AppearanceSettings(theme: bindable.settings.theme)

            Section("About") {
                LabeledContent("Version", value: BuildInfo.version)
                LabeledContent("Build", value: BuildInfo.build)
                LabeledContent("Commit", value: BuildInfo.commit)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    /// Scrolls to a section the dashboard asked for, then clears the request. Asking for
    /// the token section with no token saved opens Add Token directly.
    private func reveal(_ anchor: SettingsAnchor?, with proxy: ScrollViewProxy) {
        guard let anchor else { return }
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
            if anchor == .account, !model.hasToken { focusedField = .account }
            if anchor == .token, !model.hasToken { presentAddToken() }
            focus = nil
        }
    }

    private func presentAddToken() {
        // A sheet takes key status like a popover; see `releaseWindowFocus()`.
        releaseWindowFocus()
        addsToken = true
    }

    private func sectionHeader(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(caption).font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
        }
    }

    /// Who is measured, how, and how fresh the data is.
    private var accountSummary: some View {
        let account = model.accountLogin
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(.tint.opacity(0.16))
                if let initial = account.first {
                    Text(String(initial).uppercased())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "person.fill").foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.isEmpty ? "No account yet" : "@\(account)").font(.headline)
                Text(accountDetail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            syncStatus.font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var accountDetail: String {
        if !model.accountLogin.isEmpty { return model.connectionLabel }
        return model.hasToken ? "Checking your tokens…" : "Add a token, or enter a username below."
    }

    @ViewBuilder
    private var syncStatus: some View {
        if model.isSyncing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(model.syncStage?.label ?? "Syncing…")
            }
        } else if let synced = model.snapshot.lastSuccessfulSync {
            Text("Synced \(synced, style: .relative) ago")
        } else if !model.accountLogin.isEmpty {
            Text("Not synced yet")
        }
    }

    private var usernameCaption: String {
        guard model.hasToken else {
            return "Reads the public contribution calendar. Add a token for PR stats."
        }
        guard model.accountFromTokens else {
            return "The account comes from your tokens once GitHub confirms who owns them."
        }
        return
            "Using @\(model.accountLogin) from \(model.accountSource). This username is used again if you remove every token."
    }

    /// Opt-in for classic tokens, under the InsecuSlopometer™ headline so nobody turns it
    /// on by accident. Classic tokens are listed with the others, marked Classic.
    private func insecuSlopometer(_ bindable: Bindable<AppModel>) -> some View {
        let hasClassic = model.tokens.contains { $0.kind == .classic }
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lock.open.fill").foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("InsecuSlopometer™")
                Text(
                    hasClassic
                        ? "Remove classic tokens to turn this off."
                        : "Allows classic tokens, which can't be read-only. Not recommended."
                )
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            InfoButton("About InsecuSlopometer™") {
                Text(
                    "A classic token needs the repo scope to read private PRs, and that scope also grants write access to every repository you can reach."
                )
                Text(
                    "Slopometer only reads, but anyone who copies the token can write. Use a fine-grained token if you can. When this is on, Add Token also accepts classic tokens."
                )
            }
            Toggle("Allow classic tokens", isOn: bindable.allowsClassicTokens)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.orange)
                .disabled(hasClassic)
        }
    }

    private func applyLogin() {
        let trimmed = login.trimmingCharacters(in: .whitespaces)
        guard GitHubClient.isValidLogin(trimmed) else { return }
        model.settings.login = trimmed
    }

    /// Turning the quota off parks its counts and target so they stay visible and return.
    private func goalEnabled(_ settings: Binding<DashboardSettings>) -> Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.goal != nil },
            set: { enabled in
                if enabled {
                    settings.wrappedValue.goal = model.parkedGoal
                } else {
                    if let goal = settings.wrappedValue.goal { model.parkedGoal = goal }
                    settings.wrappedValue.goal = nil
                }
            })
    }

    /// Typed targets outside the allowed range snap to its nearest end.
    private func targetBinding(_ settings: Binding<DashboardSettings>, _ goal: Goal) -> Binding<Int>
    {
        let raw = goalBinding(settings, \.target, goal)
        return Binding(
            get: { raw.wrappedValue },
            set: {
                raw.wrappedValue = min(
                    max($0, Goal.targetRange.lowerBound), Goal.targetRange.upperBound)
            })
    }

    private func goalBinding<Value>(
        _ settings: Binding<DashboardSettings>, _ keyPath: WritableKeyPath<Goal, Value>,
        _ goal: Goal
    ) -> Binding<Value> {
        Binding(
            get: { (settings.wrappedValue.goal ?? goal)[keyPath: keyPath] },
            set: { value in
                var updated = settings.wrappedValue.goal ?? goal
                updated[keyPath: keyPath] = value
                settings.wrappedValue.goal = updated
            })
    }
}

/// Names and saves one token. The kind follows GitHub's prefix; classic tokens need the
/// InsecuSlopometer™ opt-in. The value goes straight to Keychain and is never shown again.
private struct AddTokenSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var token = ""
    @State private var message: String?
    @FocusState private var tokenFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a token").font(.title3.weight(.semibold))
                Text(
                    "Use a fine-grained token with read-only Pull requests access. It is stored in Keychain and only sent to GitHub."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Name").gridColumnAlignment(.trailing)
                    TextField("Name", text: $label, prompt: Text(namePrompt))
                        .labelsHidden()
                }
                GridRow {
                    Text("Token")
                    SecureField("Token", text: $token, prompt: Text("Paste token"))
                        .labelsHidden()
                        .focused($tokenFocused)
                        .onSubmit(save)
                }
            }
            .textFieldStyle(.roundedBorder)
            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Link("Create one on GitHub", destination: TokenGuide.creationURL)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Token", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { tokenFocused = true }
    }

    private var namePrompt: String {
        model.hasToken ? "For example, my-org" : "For example, Personal"
    }

    private func save() {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch model.addToken(token, label: label) {
        case .saved:
            token = ""
            dismiss()
            return
        case .duplicate: message = "That token is already saved."
        case .classicNotAllowed:
            message =
                "That's a classic token, which can also write. Use a fine-grained token, or allow classic tokens under InsecuSlopometer™."
        case .keychainFailed: message = "Couldn't save the token to Keychain."
        }
        token = ""
    }
}

/// Dropdown checklist of repositories with synced PRs; all are ticked by default.
private struct RepositoryPicker: View {
    @Binding var selection: [String]
    let choices: [RepositoryChoice]
    @State private var isPresented = false
    @State private var search = ""

    var body: some View {
        Button {
            releaseWindowFocus()
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(summary)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { checklist }
    }

    private var summary: String {
        selection.isEmpty ? "All repositories" : Goal.scopeLabel(for: selection)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "All repositories",
                isOn: Binding(get: { selection.isEmpty }, set: { if $0 { selection = [] } })
            )
            .disabled(selection.isEmpty)
            if choices.count > 8 {
                TextField("Filter", text: $search, prompt: Text("Search repositories"))
                    .textFieldStyle(.roundedBorder)
            }
            Divider()
            if choices.isEmpty {
                Text("No PRs synced yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(visible) { choice in row(choice) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
            }
            Text("Repositories with synced PRs. New ones are included while All is ticked.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.checkbox)
        .padding(12)
        .frame(width: 320)
    }

    private var visible: [RepositoryChoice] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return choices }
        return choices.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func row(_ choice: RepositoryChoice) -> some View {
        Toggle(
            isOn: Binding(
                get: { RepositoryFilter.isIncluded(choice.name, in: selection) },
                set: { _ in
                    selection = RepositoryFilter.toggling(
                        choice.name, in: selection, choices: choices)
                })
        ) {
            HStack {
                Text(choice.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(choice.pullRequests) PR\(choice.pullRequests == 1 ? "" : "s")")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .disabled(
            RepositoryFilter.isLastIncluded(choice.name, in: selection, choices: choices)
        )
        .help(
            RepositoryFilter.isLastIncluded(choice.name, in: selection, choices: choices)
                ? "At least one repository stays selected." : "")
    }
}

/// Moves the window's keyboard focus off any text field before a popover opens.
///
/// A popover is its own window and takes key status (the repository list has a search
/// field). When it closes, the Settings window becomes key again and restores its first
/// responder: usually the Username field, focused at launch. A text field that regains
/// focus selects its text and scrolls itself into view, so the form jumped to the top.
/// Menus (Timezone, Counts) never take key status, so they never did this. With no first
/// responder left to restore, nothing is reselected and nothing scrolls.
@MainActor
func releaseWindowFocus() {
    guard let window = NSApp.keyWindow else { return }
    if window.firstResponder is NSText || window.firstResponder is NSTextField {
        window.makeFirstResponder(nil)
    }
}

/// A small `?` that shows longer guidance in a popover, so captions stay one line.
struct InfoButton<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var isPresented = false

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Button {
            // Same focus release as the repository picker, in case this popover takes key.
            releaseWindowFocus()
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .glassIconButtonStyle()
        .controlSize(.small)
        .help(title)
        .accessibilityLabel(title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) { content() }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(width: 320, alignment: .leading)
        }
    }
}
