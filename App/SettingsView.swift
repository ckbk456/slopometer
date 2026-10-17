import SlopometerCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Binding var focus: SettingsAnchor?
    @FocusState private var focusedField: SettingsAnchor?
    @State private var login = ""

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
    }

    private func form(bindable: Bindable<AppModel>) -> some View {
        Form {
            Section {
                tierHeader(
                    1, "Public account", systemImage: "person",
                    caption:
                        "Shows the public contribution calendar, including private activity as anonymous counts if the profile shows it. Nothing secret is stored."
                )
                HStack {
                    TextField("Username", text: $login, prompt: Text("Enter username"))
                        .focused($focusedField, equals: .account)
                        .onSubmit(applyLogin)
                    Button("Save", action: applyLogin)
                        .disabled(
                            login == model.settings.login || !GitHubClient.isValidLogin(login))
                }
                .id(SettingsAnchor.account)

                tierHeader(
                    2, "Fine-grained tokens", systemImage: "key",
                    caption:
                        "Read-only access to your PRs. Unlocks PR stats, the daily quota, and repository filters. Stored in Keychain and only sent to GitHub."
                )
                ForEach(model.tokens.filter { $0.kind == .fineGrained }) { tokenRow($0) }
                VStack(alignment: .leading, spacing: 6) {
                    Link(
                        model.hasToken
                            ? "Create another fine-grained token on GitHub"
                            : "Create a fine-grained token on GitHub",
                        destination: TokenGuide.creationURL)
                    Text(
                        """
                        Resource owner: your account, or an organization
                        Repository access: All repositories
                        Permissions: Pull requests, read-only (Metadata is added automatically)
                        """
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Text(
                        "A token owned by your account can't see private repositories that belong to an organization. To count those PRs, add another token with the organization as its resource owner. The organization may need to approve it."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                TokenAdder(kind: .fineGrained, focus: $focusedField)
                    .id(SettingsAnchor.token)

                tierHeader(
                    3, "Classic tokens", systemImage: "lock.open",
                    caption:
                        "Classic tokens can't be read-only: the repo scope also grants write access to every repository you can reach. Slopometer only reads, but anyone who copies the token can write. Not recommended."
                )
                insecuSlopometer(bindable)
                if model.allowsClassicTokens {
                    ForEach(model.tokens.filter { $0.kind == .classic }) { tokenRow($0) }
                    TokenAdder(kind: .classic, focus: $focusedField)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub connections")
                    Text("From least to most access. PR stats and the daily quota need a token.")
                        .font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
                }
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
                        Text("Add a fine-grained or classic token above to use these.")
                            .font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!model.hasToken)

            Section("Timezone") {
                Picker("Timezone", selection: bindable.settings.timeZoneID) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
                Text(
                    "PR counts and the quota reset at midnight in this timezone. Contribution days are labeled by GitHub."
                )
                .font(.caption).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: BuildInfo.version)
                LabeledContent("Build", value: BuildInfo.build)
                LabeledContent("Commit", value: BuildInfo.commit)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    /// Scrolls to and focuses a section the dashboard asked for, then clears the request.
    private func reveal(_ anchor: SettingsAnchor?, with proxy: ScrollViewProxy) {
        guard let anchor else { return }
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
            if anchor == .account || !model.hasToken { focusedField = anchor }
            focus = nil
        }
    }

    private func tierHeader(
        _ number: Int, _ title: String, systemImage: String, caption: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold)).monospacedDigit()
                .frame(width: 18, height: 18)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage).font(.headline)
                Text(caption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, number == 1 ? 0 : 6)
    }

    private func tokenRow(_ entry: TokenEntry) -> some View {
        let status = model.status(of: entry)
        return HStack {
            Image(systemName: status.ok ? "key.fill" : "exclamationmark.triangle")
                .foregroundStyle(status.ok ? Color.secondary : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.label)
                    if entry.kind == .classic {
                        Text("Classic")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .foregroundStyle(.orange)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                }
                Text(status.text).font(.caption)
                    .foregroundStyle(status.ok ? Color.secondary : Color.red)
            }
            Spacer()
            Button("Remove", role: .destructive) { model.removeToken(entry.id) }
        }
    }

    /// Opt-in for classic tokens, named so nobody turns it on by accident.
    private func insecuSlopometer(_ bindable: Bindable<AppModel>) -> some View {
        let hasClassic = model.tokens.contains { $0.kind == .classic }
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: bindable.allowsClassicTokens) {
                Label {
                    Text("InsecuSlopometer™")
                } icon: {
                    Image(systemName: "lock.open.fill").foregroundStyle(.orange)
                }
            }
            .tint(.orange)
            .disabled(hasClassic)
            if hasClassic {
                Text("Remove classic tokens to turn this off.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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

/// Name and paste fields for one kind of token.
private struct TokenAdder: View {
    @Environment(AppModel.self) private var model
    let kind: AccessToken.Kind
    var focus: FocusState<SettingsAnchor?>.Binding
    @State private var label = ""
    @State private var token = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Name", text: $label, prompt: Text(namePrompt))
                    .labelsHidden()
                    .frame(width: 150)
                Group {
                    if kind == .fineGrained {
                        SecureField("Token", text: $token, prompt: Text("Paste token"))
                            .focused(focus, equals: .token)
                    } else {
                        SecureField("Token", text: $token, prompt: Text("Paste classic token"))
                    }
                }
                .labelsHidden()
                .onSubmit(save)
                Button("Add", action: save)
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
        }
    }

    private var namePrompt: String {
        model.hasToken ? "Name, e.g. my-org" : "Name, e.g. Personal"
    }

    private func save() {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch model.addToken(token, label: label, as: kind) {
        case .saved:
            message = nil
            label = ""
        case .duplicate: message = "That token is already saved."
        case .wrongKind:
            message =
                kind == .fineGrained
                ? "That looks like a classic token. Add it under Classic tokens below (turn on InsecuSlopometer™ first), or create a fine-grained token."
                : "That is a fine-grained token. Add it under Fine-grained tokens above."
        case .keychainFailed: message = "Could not save the token to Keychain."
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
                Text("No PRs synced yet. Repositories appear here after a sync.")
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
            Text(
                "Lists repositories with your synced PRs. New repositories are included while All is ticked."
            )
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
