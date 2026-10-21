import SlopometerCore
import SwiftUI

/// Chooses a saved configuration, and in the app window also saves, updates, renames,
/// and deletes them. The title names the configuration in use, marked when it was edited.
struct ConfigurationMenu: View {
    @Environment(AppModel.self) private var model
    /// The menu bar panel only switches; managing happens in the app window.
    var manages = true
    @State private var naming: Naming?
    @State private var nameText = ""
    @State private var deleting: SavedConfiguration?

    private enum Naming: Equatable {
        case save
        case rename(String)
    }

    private var settings: DashboardSettings { model.settings }

    var body: some View {
        Menu {
            ForEach(settings.savedConfigurations) { item in
                // Choosing the configuration in use again discards its edits.
                Toggle(
                    item.name,
                    isOn: Binding(
                        get: { settings.configurationID == item.id },
                        set: { _ in model.applyConfiguration(item.id) }))
            }
            if manages {
                if settings.savedConfigurations.isEmpty {
                    // Without saved ones the menu is only "Save as New…", which alone does
                    // not say what a configuration is.
                    Text("Save this dashboard setup by name to switch back to it later.")
                    Divider()
                } else {
                    Divider()
                }
                Button("Save as New Configuration…") { startNaming(.save) }
                if let current = settings.configuration {
                    Button("Update “\(current.name)”") { model.updateConfiguration() }
                        .disabled(!settings.configurationIsEdited)
                    Button("Rename “\(current.name)”…") { startNaming(.rename(current.id)) }
                    Button("Delete “\(current.name)”…", role: .destructive) {
                        deleting = current
                    }
                }
            }
        } label: {
            Label(title, systemImage: "square.stack")
        }
        .help(
            "Saved configurations: metric, repositories, chart, range, average, colors, and quota"
        )
        .accessibilityLabel("Configuration: \(title)")
        .alert(
            naming == .save ? "Save Configuration" : "Rename Configuration", isPresented: isNaming
        ) {
            TextField("Name", text: $nameText)
            Button(naming == .save ? "Save" : "Rename", action: finishNaming)
                .disabled(trimmedName.isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            if naming == .save {
                Text("Saves the metric, repositories, chart, range, average, colors, and quota.")
            }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?", isPresented: isDeleting, presenting: deleting
        ) { item in
            Button("Delete", role: .destructive) { model.deleteConfiguration(item.id) }
        } message: { _ in
            Text("The dashboard keeps showing what it shows now.")
        }
    }

    private var title: String {
        guard let current = settings.configuration else { return "Configurations" }
        return settings.configurationIsEdited ? "\(current.name) (edited)" : current.name
    }

    private var trimmedName: String { nameText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isNaming: Binding<Bool> {
        Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func startNaming(_ purpose: Naming) {
        releaseWindowFocus()
        switch purpose {
        case .save:
            nameText = "Configuration \(settings.savedConfigurations.count + 1)"
        case .rename(let id):
            nameText = settings.savedConfigurations.first { $0.id == id }?.name ?? ""
        }
        naming = purpose
    }

    private func finishNaming() {
        let name = trimmedName
        guard !name.isEmpty, let purpose = naming else { return }
        switch purpose {
        case .save: model.saveConfiguration(named: name)
        case .rename(let id): model.renameConfiguration(id, to: name)
        }
        naming = nil
    }
}
