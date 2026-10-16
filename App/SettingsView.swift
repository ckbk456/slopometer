import SlopometerCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var login = ""
    @State private var token = ""
    @State private var tokenMessage: String?
    @State private var repositories = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("GitHub account") {
                HStack {
                    TextField("Username", text: $login, prompt: Text("octocat"))
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

            Section("GitHub token (optional)") {
                Text(
                    "A token unlocks PRs opened, authored PRs merged, the daily PR quota, the exact PRs behind each count, and repository filters. Create a fine-grained token with read-only Pull requests and Metadata access for the repositories you want counted. It is stored in Keychain and only sent to GitHub."
                )
                .font(.caption).foregroundStyle(.secondary)
                Link(
                    "Create a fine-grained token on GitHub",
                    destination: URL(
                        string: "https://github.com/settings/personal-access-tokens/new")!)
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
                        SecureField("Token", text: $token)
                        Button("Save") {
                            tokenMessage =
                                model.saveToken(token)
                                ? nil : "Could not save the token to Keychain."
                            token = ""
                        }
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let tokenMessage { Text(tokenMessage).foregroundStyle(.red) }
            }

            Section("Pull requests (token)") {
                TextField(
                    "Repository filter", text: $repositories,
                    prompt: Text("All readable repositories, or owner/name, owner/other")
                )
                .onSubmit(applyRepositories)
                .disabled(!model.hasToken)
                Toggle("Daily PR quota", isOn: goalEnabled($model.settings))
                    .disabled(!model.hasToken)
                if let goal = model.settings.goal {
                    Picker("Counts", selection: goalBinding($model.settings, \.metric, goal)) {
                        Text(Metric.prsMerged.unit).tag(Metric.prsMerged)
                        Text(Metric.prsOpened.unit).tag(Metric.prsOpened)
                    }
                    Stepper(
                        "Target: \(goal.target) per day",
                        value: goalBinding($model.settings, \.target, goal), in: 1...100)
                }
            }

            Section("Days") {
                Picker("Timezone", selection: $model.settings.timeZoneID) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
                Text(
                    "PR counts and the quota reset at midnight in this timezone. Contribution days are labeled by GitHub."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            login = model.settings.login
            repositories = model.settings.repositories.joined(separator: ", ")
        }
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
