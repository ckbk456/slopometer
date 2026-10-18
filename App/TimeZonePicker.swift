import SlopometerCore
import SwiftUI

/// Settings › Timezone: a searchable list instead of a menu of 400 IANA identifiers.
/// Zones run west to east with their current GMT offset; search matches city, region,
/// identifier, the system's zone name, or an offset ("+7").
struct TimeZonePicker: View {
    @Binding var selection: String
    @State private var isPresented = false
    @State private var search = ""
    @State private var choices: [TimeZoneChoice] = []
    @FocusState private var searchFocused: Bool

    private var current: TimeZoneChoice? { TimeZoneChoice(identifier: selection) }

    var body: some View {
        Button {
            releaseWindowFocus()
            search = ""
            choices = TimeZoneChoice.all()
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(current?.summary ?? selection)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
        }
        .help(selection)
        .accessibilityLabel("Timezone")
        .accessibilityValue(current.map { "\($0.city), \($0.offset)" } ?? selection)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { list }
    }

    private var visible: [TimeZoneChoice] { choices.filter { $0.matches(search) } }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search", text: $search, prompt: Text("City, region, or offset like +7"))
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { if let first = visible.first { choose(first.id) } }
            let mac = TimeZone.current.identifier
            if mac != selection {
                Button {
                    choose(mac)
                } label: {
                    Label(
                        "Use This Mac's Timezone (\(TimeZoneChoice(identifier: mac)?.summary ?? mac))",
                        systemImage: "location")
                }
                .buttonStyle(.borderless)
            }
            Divider()
            if visible.isEmpty {
                Text("No timezone matches “\(search)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visible) { row($0) }
                        }
                    }
                    .frame(height: 300)
                    .onAppear { proxy.scrollTo(selection, anchor: .center) }
                }
            }
        }
        .padding(12)
        .frame(width: 360)
        .onAppear { searchFocused = true }
    }

    private func row(_ choice: TimeZoneChoice) -> some View {
        let isSelected = choice.id == selection
        return Button {
            choose(choice.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .opacity(isSelected ? 1 : 0)
                    .foregroundStyle(.tint)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.city)
                    if !choice.region.isEmpty || choice.name != nil {
                        Text(
                            [choice.region, choice.name ?? ""].filter { !$0.isEmpty }
                                .joined(separator: " · ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(choice.offset)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(
                isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .id(choice.id)
        .help(choice.id)
        .accessibilityLabel("\(choice.city), \(choice.region), \(choice.offset)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ id: String) {
        selection = id
        isPresented = false
    }
}
