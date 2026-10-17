import SlopometerCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Binding var focus: SettingsAnchor?
    @FocusState private var focusedField: SettingsAnchor?
    @State private var login = ""
    @State private var token = ""
    @State private var tokenMessage: String?
    @State private var repositories = ""

    var body: some View {
        @Bindable var model = model
        ScrollViewReader { proxy in
            form(bindable: $model)
                .onAppear { reveal(focus, with: proxy) }
                .onChange(of: focus) { _, anchor in reveal(anchor, with: proxy) }
        }
        .onAppear {
            login = model.settings.login
            repositories = model.settings.repositories.joined(separator: ", ")
        }
    }

    private func form(bindable: Bindable<AppModel>) -> some View {
        Form {
            Section("GitHub account") {
                HStack {
                    TextField("Username", text: $login, prompt: Text("Enter username"))
                        .focused($focusedField, equals: .account)
                        .onSubmit(applyLogin)
                    Button("Save", action: applyLogin)
                        .disabled(
                            login == model.settings.login || !GitHubClient.isValidLogin(login))
                }
                Text(
                    "A username alone shows the account's public contribution calendar, including private activity as anonymous counts if the profile shows it."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .id(SettingsAnchor.account)

            Section {
                Text(
                    "A token unlocks PRs opened, authored PRs merged, the daily PR quota, the exact PRs behind each count, and repository filters. It is stored in Keychain and only sent to GitHub."
                )
                .font(.caption).foregroundStyle(.secondary)
                if !model.hasToken {
                    VStack(alignment: .leading, spacing: 6) {
                        Link(
                            "Create a fine-grained token on GitHub",
                            destination: TokenGuide.creationURL)
                        Text(
                            """
                            Resource owner: your account
                            Repository access: All repositories
                            Permissions: Pull requests, read-only (Metadata is added automatically)
                            """
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(
                            "PRs in private repositories owned by an organization are counted only if the token's resource owner is that organization."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.hasToken {
                    HStack {
                        Label(
                            tokenStatus,
                            systemImage: model.tokenUsable ? "key.fill" : "exclamationmark.triangle"
                        )
                        Spacer()
                        Button("Remove Token", role: .destructive) { model.removeToken() }
                    }
                } else {
                    HStack {
                        SecureField("Token", text: $token, prompt: Text("Paste token"))
                            .focused($focusedField, equals: .token)
                            .onSubmit(saveToken)
                        Button("Save", action: saveToken)
                            .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let tokenMessage { Text(tokenMessage).foregroundStyle(.red) }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub token")
                    Text("Optional for contributions. Required for PR stats and the daily quota.")
                        .font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
                }
            }
            .id(SettingsAnchor.token)

            Section("Pull requests (requires a token)") {
                TextField(
                    "Repository filter", text: $repositories,
                    prompt: Text("All readable repositories, or owner/name, owner/other")
                )
                .onSubmit(applyRepositories)
                .disabled(!model.hasToken)
                Toggle("Daily PR quota", isOn: goalEnabled(bindable.settings))
                    .disabled(!model.hasToken)
                if !model.hasToken {
                    Text("Add a token above to filter repositories and set a daily PR quota.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let goal = model.settings.goal {
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
            }

            Section("Days") {
                Picker("Timezone", selection: bindable.settings.timeZoneID) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
                Text(
                    "PR counts and the quota reset at midnight in this timezone. Contribution days are labeled by GitHub."
                )
                .font(.caption).foregroundStyle(.secondary)
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

    private func saveToken() {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        tokenMessage = model.saveToken(token) ? nil : "Could not save the token to Keychain."
        token = ""
    }

    private var tokenStatus: String {
        if case .tokenOwnerMismatch(_, let actual) = model.lastReport?.pullRequestError {
            return "Token belongs to \(actual)"
        }
        if model.lastReport?.pullRequestError == .unauthorized { return "Token rejected by GitHub" }
        if model.lastReport?.tokenVerified == true {
            return "Token verified for @\(model.settings.login)"
        }
        return "Token saved in Keychain"
    }

    private func applyLogin() {
        let trimmed = login.trimmingCharacters(in: .whitespaces)
        guard GitHubClient.isValidLogin(trimmed) else { return }
        model.settings.login = trimmed
    }

    private func applyRepositories() {
        model.settings.repositories = repositories.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.split(separator: "/").count == 2 }
    }

    private func goalEnabled(_ settings: Binding<DashboardSettings>) -> Binding<Bool> {
        Binding(
            get: { settings.wrappedValue.goal != nil },
            set: { settings.wrappedValue.goal = $0 ? Goal() : nil })
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
