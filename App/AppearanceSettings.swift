import AppKit
import SlopometerCore
import SwiftUI

/// Settings › Appearance: a preset, or the person's own edit of one. Only the activity
/// gradient, accent, average line, mapping, and meter are themable; text and window
/// backgrounds stay with the system so no choice can make labels unreadable.
///
/// Edits go to a local draft first so color drags redraw the preview at once, then reach
/// the model after a short pause; every settings change rebuilds the snapshot and widget.
struct AppearanceSettings: View {
    @Binding var theme: ColorTheme
    @State private var draft: ColorTheme
    /// Which appearance's palette the editor changes; light while dark mode shares it.
    @State private var editsDark = false
    @State private var selectedStop = 0
    @State private var hexText = ""
    @Environment(\.colorScheme) private var colorScheme

    init(theme: Binding<ColorTheme>) {
        _theme = theme
        _draft = State(initialValue: theme.wrappedValue)
    }

    var body: some View {
        // Modifiers on one section only; on a group they would repeat for each section.
        presetsSection
            .task(id: draft) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                commit()
            }
            .onChange(of: theme) { _, saved in
                if saved != draft { draft = saved }
            }
            .onDisappear(perform: commit)
        colorsSection
        previewSection
    }

    private func commit() {
        if theme != draft { theme = draft }
    }

    // MARK: Presets

    private var presetsSection: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: 10)],
                alignment: .leading, spacing: 10
            ) {
                ForEach(ThemePreset.all) { preset in
                    PresetSwatch(
                        preset: preset, isDark: colorScheme == .dark,
                        isSelected: draft.presetID == preset.id
                    ) { choose(preset.theme) }
                }
            }
            .padding(.vertical, 2)
            HStack(alignment: .firstTextBaseline) {
                Label("Colorblind-safe", systemImage: "eye")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset to Slop Green") { choose(ColorTheme.standard) }
                    .disabled(draft == ColorTheme.standard)
            }
        } header: {
            header(
                "Appearance",
                caption:
                    "Colors for activity, the accent, and the average line. Text follows the system."
            )
        }
    }

    /// Presets apply at once, without the editing pause.
    private func choose(_ preset: ColorTheme) {
        draft = preset
        theme = preset
        selectedStop = 0
        if preset.dark == nil { editsDark = false }
    }

    // MARK: Colors

    private var colorsSection: some View {
        Section {
            HStack {
                Picker("Editing", selection: $editsDark) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(draft.dark == nil)
                Spacer()
                Toggle("Same colors in dark mode", isOn: sharesDark)
            }
            GradientEditor(
                colors: palette.gradient, selection: stopIndex,
                select: { selectedStop = $0 })
            stopControls
            HStack(alignment: .firstTextBaseline) {
                Picker("Mapping", selection: field(\.mapping)) {
                    ForEach(ColorMapping.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                InfoButton("About mapping") {
                    Text(
                        "4 levels works like GitHub: each day is one of four colors, scaled to the busiest day shown."
                    )
                    Text(
                        "Smooth gives every count its own color along the gradient, from 1 to the busiest day. It suits rainbows and gradients with many colors."
                    )
                }
            }
            Text(
                draft.mapping == .levels
                    ? "Four steps from the gradient, like GitHub."
                    : "Every count gets its own color. Best for rainbows."
            )
            .font(.caption).foregroundStyle(.secondary)
            Picker("Quota meter", selection: field(\.meter)) {
                ForEach(MeterColoring.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            HStack {
                Toggle("Automatic accent", isOn: automaticAccent)
                Spacer()
                if let accent = palette.accent {
                    ColorPicker(
                        "Accent",
                        selection: colorBinding { _ in
                            accent
                        } set: {
                            $0.accent = $1
                        },
                        supportsOpacity: false)
                }
            }
            Text(
                "Tints controls, badges, and highlighted numbers. Automatic uses the strongest gradient color."
            )
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            ColorPicker(
                "Average line",
                selection: colorBinding {
                    $0.trend
                } set: {
                    $0.trend = $1
                },
                supportsOpacity: false)
        } header: {
            header(
                "Colors",
                caption: ThemePreset.preset(id: draft.presetID).map { "Preset: \($0.name)" }
                    ?? "Custom")
        }
    }

    /// The selected stop's color, hex, and the gradient-wide actions.
    private var stopControls: some View {
        let count = palette.gradient.count
        return HStack(spacing: 8) {
            ColorPicker(
                "Color \(stopIndex + 1) of \(count)",
                selection: colorBinding {
                    $0.gradient[stopIndex]
                } set: {
                    $0.gradient[stopIndex] = $1
                },
                supportsOpacity: false
            )
            .fixedSize()
            TextField("Hex", text: $hexText, prompt: Text("#RRGGBB"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(width: 92)
                .accessibilityLabel("Hex for color \(stopIndex + 1)")
                .onSubmit(applyHex)
            Spacer()
            ControlGroup {
                Button("Add color", systemImage: "plus", action: addStop)
                    .disabled(count >= ColorTheme.maxColors)
                    .help("Add a color after this one")
                Button("Remove color", systemImage: "minus", action: removeStop)
                    .disabled(count <= ColorTheme.minColors)
                    .help("Remove this color")
            }
            .fixedSize()
            Button("Reverse", systemImage: "arrow.left.arrow.right") {
                editPalette { $0.gradient.reverse() }
                selectedStop = count - 1 - stopIndex
            }
            .help("Reverse the gradient")
            Button("Surprise me", systemImage: "dice", action: surprise)
                .help("Random colors that still run from light to dark")
        }
        .labelStyle(.iconOnly)
        .onAppear { hexText = palette.gradient[stopIndex].hexString }
        .onChange(of: palette.gradient[stopIndex]) { _, color in hexText = color.hexString }
    }

    private func applyHex() {
        if let color = ThemeColor(hexString: hexText) {
            editPalette { $0.gradient[stopIndex] = color }
        }
        hexText = palette.gradient[stopIndex].hexString
    }

    /// Inserts the midpoint of the selected color and its right neighbor (left at the end).
    private func addStop() {
        let index = stopIndex
        editPalette { palette in
            let colors = palette.gradient
            guard colors.count < ColorTheme.maxColors else { return }
            if index + 1 < colors.count {
                palette.gradient.insert(
                    colors[index].mixed(with: colors[index + 1], by: 0.5), at: index + 1)
            } else {
                palette.gradient.insert(
                    colors[index - 1].mixed(with: colors[index], by: 0.5), at: index)
            }
        }
        selectedStop = index + 1 < palette.gradient.count - 1 ? index + 1 : index
    }

    private func removeStop() {
        let index = stopIndex
        editPalette { palette in
            guard palette.gradient.count > ColorTheme.minColors else { return }
            palette.gradient.remove(at: index)
        }
        selectedStop = max(0, index - 1)
    }

    /// Evenly spaced hues from a random start, ordered by lightness for the appearance
    /// being edited: light to dark on light backgrounds, dark to bright on dark ones.
    private func surprise() {
        let count = palette.gradient.count
        let dark = editsDark && draft.dark != nil
        let start = Double.random(in: 0..<1)
        let span = Double.random(in: 0.15...0.6) * (Bool.random() ? 1 : -1)
        let colors = (0..<count).map { index in
            let t = count > 1 ? Double(index) / Double(count - 1) : 1
            let hue = (start + span * t).truncatingRemainder(dividingBy: 1) + 1
            let brightness = dark ? 0.35 + 0.6 * t : 0.95 - 0.5 * t
            let saturation = dark ? 0.85 - 0.25 * t : 0.4 + 0.45 * t
            return themeColor(
                NSColor(
                    hue: hue.truncatingRemainder(dividingBy: 1), saturation: saturation,
                    brightness: brightness, alpha: 1))
        }
        editPalette { $0.gradient = colors }
    }

    // MARK: Preview and advice

    private var previewSection: some View {
        Section {
            let resolved = draft.resolved()
            HStack(spacing: 12) {
                ThemePreview(title: "Light")
                    .slopTheme(resolved)
                    .environment(\.colorScheme, .light)
                    .background(Color(SlopTheme.lightBackground), in: .rect(cornerRadius: 10))
                ThemePreview(title: "Dark")
                    .slopTheme(resolved)
                    .environment(\.colorScheme, .dark)
                    .background(Color(SlopTheme.darkBackground), in: .rect(cornerRadius: 10))
            }
            let advice = ThemeAdvice.check(draft)
            if !advice.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(advice, id: \.message) { item in
                        Label(item.message, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } header: {
            header("Preview", caption: "Sample data, not your activity.")
        }
    }

    private func header(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(caption).font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
        }
    }

    // MARK: Editing

    private var palette: ColorTheme.Palette { draft.palette(isDark: editsDark) }

    private var stopIndex: Int { min(max(selectedStop, 0), palette.gradient.count - 1) }

    /// Changes the palette being edited. Any edit makes the theme custom.
    private func editPalette(_ change: (inout ColorTheme.Palette) -> Void) {
        var updated = draft
        if editsDark, var dark = updated.dark {
            change(&dark)
            updated.dark = dark
        } else {
            change(&updated.light)
        }
        guard updated != draft else { return }
        updated.presetID = nil
        draft = updated
    }

    private func field<Value: Equatable>(_ keyPath: WritableKeyPath<ColorTheme, Value>)
        -> Binding<Value>
    {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { value in
                guard draft[keyPath: keyPath] != value else { return }
                draft[keyPath: keyPath] = value
                draft.presetID = nil
            })
    }

    private func colorBinding(
        get: @escaping (ColorTheme.Palette) -> ThemeColor,
        set: @escaping (inout ColorTheme.Palette, ThemeColor) -> Void
    ) -> Binding<Color> {
        Binding(
            get: { Color(get(palette)) },
            set: { color in editPalette { set(&$0, themeColor(NSColor(color))) } })
    }

    /// Off copies the light colors into dark so editing starts from what is shown.
    private var sharesDark: Binding<Bool> {
        Binding(
            get: { draft.dark == nil },
            set: { shares in
                if shares {
                    draft.dark = nil
                    draft.presetID = nil
                    editsDark = false
                } else if draft.dark == nil {
                    draft.dark = draft.light
                }
            })
    }

    /// Manual starts from the automatic color so nothing jumps.
    private var automaticAccent: Binding<Bool> {
        Binding(
            get: { palette.accent == nil },
            set: { automatic in
                let current = draft.resolved().appearance(isDark: editsDark).accent
                editPalette { $0.accent = automatic ? nil : current }
            })
    }
}

/// sRGB components of an AppKit color; extended-range values are clamped.
private func themeColor(_ color: NSColor) -> ThemeColor {
    let srgb = color.usingColorSpace(.sRGB) ?? color
    func clamp(_ value: CGFloat) -> Double { min(max(Double(value), 0), 1) }
    return ThemeColor(
        red: clamp(srgb.redComponent), green: clamp(srgb.greenComponent),
        blue: clamp(srgb.blueComponent))
}

/// A preset's gradient for the current appearance with its name. Selection shows as a
/// checkmark and a heavier outline, not only color.
private struct PresetSwatch: View {
    let preset: ThemePreset
    let isDark: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                shape
                    .fill(
                        LinearGradient(
                            colors: preset.theme.palette(isDark: isDark).gradient.map(Color.init),
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: 24)
                    .overlay {
                        shape.strokeBorder(
                            isSelected ? Color.primary : Color.primary.opacity(0.15),
                            lineWidth: isSelected ? 2 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black)
                                .font(.caption)
                                .padding(3)
                        }
                    }
                HStack(spacing: 3) {
                    Text(preset.name)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if preset.isColorblindSafe {
                        Image(systemName: "eye").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(preset.isColorblindSafe ? "\(preset.name), colorblind-safe" : preset.name)
        .accessibilityLabel(
            preset.isColorblindSafe ? "\(preset.name), colorblind-safe" : preset.name
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The gradient with one handle per color, evenly spaced like the colors themselves.
private struct GradientEditor: View {
    let colors: [ThemeColor]
    let selection: Int
    let select: (Int) -> Void

    private static let handle: CGFloat = 20

    var body: some View {
        VStack(spacing: 6) {
            // Inset by half a handle so each handle sits under its color's position.
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: colors.map(Color.init), startPoint: .leading,
                        endPoint: .trailing)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.15))
                }
                .frame(height: 28)
                .padding(.horizontal, Self.handle / 2)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(colors.indices, id: \.self) { index in
                    if index > 0 { Spacer(minLength: 4) }
                    stop(index)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func stop(_ index: Int) -> some View {
        let isSelected = index == selection
        return Button {
            select(index)
        } label: {
            Circle()
                .fill(Color(colors[index]))
                .overlay {
                    Circle().strokeBorder(
                        isSelected ? Color.primary : Color.primary.opacity(0.25),
                        lineWidth: isSelected ? 2.5 : 1)
                }
                .padding(isSelected ? 0 : 3)
                .frame(width: Self.handle, height: Self.handle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(colors[index].hexString)
        .accessibilityLabel("Color \(index + 1) of \(colors.count), \(colors[index].hexString)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One appearance's sample: a week of tiles, a column chart, and the quota meter. Apply
/// `slopTheme(_:)` and then the color scheme so the theme resolves for that scheme.
private struct ThemePreview: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(Sample.week) { point in
                    DayTile(point: point, busiest: Sample.weekBusiest, textStyle: .caption2)
                        .frame(height: 22)
                }
            }
            SlopChart(points: Sample.month, style: .columns, unit: "contributions", compact: true)
                .frame(height: 54)
            QuotaMeter(count: 3, target: 5, height: 8)
        }
        .foregroundStyle(.primary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) preview with sample data")
    }
}

/// Fixed sample counts for the preview, so it looks the same for everyone.
private enum Sample {
    static let weekBusiest = 6
    static let week = points(Array(0...6), averages: false)
    static let month = points(
        [2, 4, 1, 0, 6, 8, 3, 5, 7, 2, 9, 4, 6, 10, 3, 7, 5, 8, 11, 6, 4], averages: true)

    /// `Point` has no public initializer, so samples are decoded from their coded form.
    private static func points(_ counts: [Int], averages: Bool) -> [DashboardSnapshot.Point] {
        struct Coded: Encodable {
            let day: String
            let count: Int
            let average: Double?
            let isIncomplete = false
        }
        let start = CalendarDay(year: 2026, month: 1, day: 4)!
        let coded = counts.indices.map { index in
            let window = counts[max(0, index - 6)...index]
            return Coded(
                day: start.adding(days: index).description, count: counts[index],
                average: averages
                    ? Double(window.reduce(0, +)) / Double(window.count) : nil)
        }
        guard let data = try? JSONEncoder().encode(coded),
            let decoded = try? JSONDecoder().decode([DashboardSnapshot.Point].self, from: data)
        else { return [] }
        return decoded
    }
}
