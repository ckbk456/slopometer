import SwiftUI

/// The window's section switcher. On macOS 26 and later: a glass capsule track with a pill
/// that slides to the chosen section, inset evenly so the pill follows the track's curve.
/// Before macOS 26 (and with SDKs that have no glass API): the standard segmented control.
struct SectionPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
    }

    @Binding var selection: Value
    let options: [Option]
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The gap between the track and the pill; the pill's radius is the track's minus this.
    private static var inset: CGFloat { 3 }

    var body: some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                glassTrack
            } else {
                segmented
            }
        #else
            segmented
        #endif
    }

    private var segmented: some View {
        Picker("Section", selection: $selection) {
            ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    #if compiler(>=6.2)
        @available(macOS 26, *)
        private var glassTrack: some View {
            HStack(spacing: 0) {
                ForEach(options, id: \.value) { option in
                    segment(option)
                }
            }
            .padding(Self.inset)
            .glassEffect(.regular, in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Section")
        }
    #endif

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                selection = option.value
            }
        } label: {
            Text(option.title)
                // One weight for every state, so choosing a section never shifts the others.
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.primary.opacity(0.1))
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
