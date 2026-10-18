import AppKit
import SlopometerCore
import SwiftUI

/// Settings › Appearance: light, dark, or system, then a preset, a saved theme, or the
/// person's own edit of one. Only the activity gradient, accent, average line, mapping,
/// and meter are themable; text and window backgrounds follow the chosen appearance so no
/// choice can make labels unreadable.
///
/// Edits go to a local draft first so color drags redraw the preview at once, then reach
/// the model after a short pause; every settings change rebuilds the snapshot and widget.
struct AppearanceSettings: View {
    @Binding var theme: ColorTheme
    @Binding var saved: [SavedTheme]
    @Binding var appearance: AppearanceMode
    @State private var draft: ColorTheme
    /// The preset or saved theme the draft started from; kept after edits so a saved
    /// theme can be updated in place.
    @State private var origin: String?
    /// Which appearance's palette the editor changes; light while dark mode shares it.
    @State private var editsDark = false
    /// Dark colors set aside while dark mode shares the light ones, so turning sharing
    /// off again restores them instead of starting over.
    @State private var setAsideDark: ColorTheme.Palette?
    @State private var selectedStop = 0
    /// The stop whose color popover is open.
    @State private var editingStop: Int?
    @State private var naming: Naming?
    @State private var nameText = ""
    @State private var deleting: SavedTheme?
    @Environment(\.colorScheme) private var colorScheme

    private enum Naming: Equatable {
        case save
        case rename(String)
    }

    init(
        theme: Binding<ColorTheme>, saved: Binding<[SavedTheme]>,
        appearance: Binding<AppearanceMode>
    ) {
        _theme = theme
        _saved = saved
        _appearance = appearance
        _draft = State(initialValue: theme.wrappedValue)
        _origin = State(initialValue: theme.wrappedValue.presetID)
    }

    var body: some View {
        // Modifiers on one section only; on a group they would repeat for each section.
        presetsSection
            .id(SettingsAnchor.appearance)
            .task(id: draft) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                commit()
            }
            .onChange(of: theme) { _, saved in
                if saved != draft { draft = saved }
            }
            .onAppear { editsDark = colorScheme == .dark && draft.dark != nil }
            .onDisappear(perform: commit)
            .alert(namingTitle, isPresented: isNaming) {
                TextField("Name", text: $nameText)
                Button(naming == .save ? "Save" : "Rename", action: finishNaming)
                    .disabled(trimmedName.isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete “\(deleting?.name ?? "")”?", isPresented: isDeleting,
                presenting: deleting
            ) { item in
                Button("Delete", role: .destructive) { delete(item) }
            } message: { _ in
                Text("The colors in use now stay until you choose another theme.")
            }
        colorsSection
        previewSection
    }

    private func commit() {
        if theme != draft { theme = draft }
    }

    // MARK: Presets and saved themes

    private var presetsSection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            LazyVGrid(columns: swatchColumns, alignment: .leading, spacing: 10) {
                ForEach(ThemePreset.all) { preset in
                    PresetSwatch(
                        name: preset.name, theme: preset.theme,
                        isColorblindSafe: preset.isColorblindSafe,
                        isDark: colorScheme == .dark,
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
            if !saved.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your themes").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: swatchColumns, alignment: .leading, spacing: 10) {
                        ForEach(saved) { item in
                            PresetSwatch(
                                name: item.name, theme: item.theme, isColorblindSafe: false,
                                isDark: colorScheme == .dark, showsBothAppearances: true,
                                isSelected: draft.presetID == item.id
                            ) { choose(item.theme) }
                            .contextMenu { savedMenu(item) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack(alignment: .firstTextBaseline) {
                if let source = savedOrigin, draft.presetID != source.id {
                    Button("Update “\(source.name)”") { update(source) }
                        .help("Replace this saved theme's colors with the ones shown")
                }
                Button("Save as New Theme…") { startNaming(.save) }
                    .help("Keep these colors under your own name")
                Spacer()
                if !saved.isEmpty {
                    Text("Right-click a saved theme to rename or delete it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            header(
                "Appearance",
                caption:
                    "Light or Dark applies to the window, menu bar panel, and widget. Colors cover activity, the accent, and the average line."
            )
        }
    }

    private var swatchColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: 10)]
    }

    @ViewBuilder
    private func savedMenu(_ item: SavedTheme) -> some View {
        Button("Rename…") { startNaming(.rename(item.id)) }
        Button("Update with Current Colors") { update(item) }
            .disabled(draft.presetID == item.id)
        Divider()
        Button("Delete…", role: .destructive) { deleting = item }
    }

    /// Presets and saved themes apply at once, without the editing pause.
    private func choose(_ preset: ColorTheme) {
        draft = preset
        theme = preset
        origin = preset.presetID
        selectedStop = 0
        editingStop = nil
        setAsideDark = nil
        if preset.dark == nil { editsDark = false }
    }

    /// The preset or saved theme the draft came from, as it was chosen.
    private var originTheme: ColorTheme? {
        ThemePreset.preset(id: origin)?.theme ?? savedOrigin?.theme
    }

    private var savedOrigin: SavedTheme? { saved.first { $0.id == origin } }

    private func update(_ item: SavedTheme) {
        guard let index = saved.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = draft
        updated.presetID = item.id
        saved[index].theme = updated
        choose(updated)
    }

    private func delete(_ item: SavedTheme) {
        saved.removeAll { $0.id == item.id }
        if origin == item.id { origin = nil }
        if draft.presetID == item.id {
            draft.presetID = nil
            commit()
        }
    }

    private var trimmedName: String { nameText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var namingTitle: String { naming == .save ? "Save Theme" : "Rename Theme" }

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
            nameText = "My Theme \(saved.count + 1)"
        case .rename(let id):
            nameText = saved.first { $0.id == id }?.name ?? ""
        }
        naming = purpose
    }

    private func finishNaming() {
        let name = trimmedName
        guard !name.isEmpty, let purpose = naming else { return }
        switch purpose {
        case .save:
            let item = SavedTheme(name: name, theme: draft)
            saved.append(item)
            choose(item.theme)
        case .rename(let id):
            if let index = saved.firstIndex(where: { $0.id == id }) { saved[index].name = name }
        }
        naming = nil
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
            if draft.dark == nil, setAsideDark != nil {
                Text("Your dark colors are kept. Turn this off to get them back.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GradientEditor(
                colors: palette.gradient, selection: stopIndex, editing: $editingStop,
                select: { selectedStop = $0 }, move: moveStop,
                color: { index in
                    themeColorBinding {
                        $0.gradient[min(index, $0.gradient.count - 1)]
                    } set: {
                        if index < $0.gradient.count { $0.gradient[index] = $1 }
                    }
                },
                remove: removeStop)
            gradientActions
            Text("Click a color to change it. Drag a color left or right to reorder.")
                .font(.caption).foregroundStyle(.secondary)
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
                    ColorSwatchButton(
                        title: "Accent",
                        color: themeColorBinding { _ in
                            accent
                        } set: {
                            $0.accent = $1
                        }
                    )
                    .fixedSize()
                }
            }
            Text(
                "Tints controls, badges, and highlighted numbers. Automatic uses the strongest gradient color."
            )
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            ColorSwatchButton(
                title: "Average line",
                color: themeColorBinding {
                    $0.trend
                } set: {
                    $0.trend = $1
                })
        } header: {
            header("Colors", caption: themeCaption)
        }
    }

    private var themeCaption: String {
        if let preset = ThemePreset.preset(id: draft.presetID) { return "Preset: \(preset.name)" }
        if let item = saved.first(where: { $0.id == draft.presetID }) {
            return "Your theme: \(item.name)"
        }
        if let item = savedOrigin { return "Edited from “\(item.name)”, not saved" }
        if let preset = ThemePreset.preset(id: origin) {
            return "Edited from \(preset.name), not saved"
        }
        return "Custom, not saved"
    }

    /// Whole-gradient actions, titled so each says what it does.
    private var gradientActions: some View {
        let count = palette.gradient.count
        return HStack(spacing: 8) {
            Button("Add Color", systemImage: "plus", action: addStop)
                .disabled(count >= ColorTheme.maxColors)
                .help(
                    count >= ColorTheme.maxColors
                        ? "Up to \(ColorTheme.maxColors) colors"
                        : "Add a color after the selected one, halfway to its neighbor")
            Button("Reverse", systemImage: "arrow.left.arrow.right") {
                editPalette { $0.gradient.reverse() }
                selectedStop = count - 1 - stopIndex
            }
            .help("Flip the gradient so the most active days get the first color")
            Button("Surprise Me", systemImage: "dice", action: surprise)
                .help("Random colors that still run from light to dark")
            Spacer()
        }
        .labelStyle(.titleAndIcon)
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

    private func removeStop(_ index: Int) {
        editingStop = nil
        editPalette { palette in
            guard palette.gradient.count > ColorTheme.minColors,
                palette.gradient.indices.contains(index)
            else { return }
            palette.gradient.remove(at: index)
        }
        selectedStop = max(0, index - 1)
    }

    private func moveStop(from source: Int, to destination: Int) {
        guard source != destination else { return }
        editPalette { palette in
            let color = palette.gradient.remove(at: source)
            palette.gradient.insert(color, at: destination)
        }
        selectedStop = destination
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
            return ThemeColor(
                hue: hue.truncatingRemainder(dividingBy: 1),
                saturation: dark ? 0.85 - 0.25 * t : 0.4 + 0.45 * t,
                brightness: dark ? 0.35 + 0.6 * t : 0.95 - 0.5 * t)
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

    private func themeColorBinding(
        get: @escaping (ColorTheme.Palette) -> ThemeColor,
        set: @escaping (inout ColorTheme.Palette, ThemeColor) -> Void
    ) -> Binding<ThemeColor> {
        Binding(
            get: { get(palette) },
            set: { color in editPalette { set(&$0, color) } })
    }

    /// On sets the dark colors aside rather than discarding them; off brings them back,
    /// or copies the light colors so editing starts from what is shown. Returning to the
    /// chosen theme's own colors keeps it selected.
    private var sharesDark: Binding<Bool> {
        Binding(
            get: { draft.dark == nil },
            set: { shares in
                var updated = draft
                if shares {
                    guard let dark = updated.dark else { return }
                    setAsideDark = dark
                    updated.dark = nil
                    editsDark = false
                } else {
                    guard updated.dark == nil else { return }
                    updated.dark = setAsideDark ?? updated.light
                    setAsideDark = nil
                    editsDark = true
                }
                updated.presetID = nil
                if let source = originTheme, source.dark == updated.dark,
                    source.light == updated.light,
                    source.mapping == updated.mapping, source.meter == updated.meter
                {
                    updated.presetID = source.presetID
                }
                draft = updated
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

/// A theme's gradient for the current appearance with its name; a saved theme with its
/// own dark colors shows light above dark, since those can differ entirely. Selection
/// shows as a checkmark and a heavier outline, not only color.
private struct PresetSwatch: View {
    let name: String
    let theme: ColorTheme
    let isColorblindSafe: Bool
    let isDark: Bool
    var showsBothAppearances = false
    let isSelected: Bool
    let action: () -> Void

    private var isSplit: Bool { showsBothAppearances && theme.dark != nil }

    private func strip(isDark: Bool) -> some View {
        LinearGradient(
            colors: theme.palette(isDark: isDark).gradient.map(Color.init),
            startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                VStack(spacing: 0) {
                    if isSplit {
                        strip(isDark: false)
                        strip(isDark: true)
                    } else {
                        strip(isDark: isDark)
                    }
                }
                .frame(height: 24)
                .clipShape(shape)
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
                    Text(name)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if isColorblindSafe {
                        Image(systemName: "eye").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(
            isColorblindSafe
                ? "\(name), colorblind-safe"
                : isSplit ? "\(name): light colors above, dark below" : name
        )
        .accessibilityLabel(isColorblindSafe ? "\(name), colorblind-safe" : name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The gradient with one handle per color, evenly spaced like the colors themselves.
/// Clicking a handle opens its color in a popover; dragging it reorders the gradient.
private struct GradientEditor: View {
    let colors: [ThemeColor]
    let selection: Int
    @Binding var editing: Int?
    let select: (Int) -> Void
    let move: (Int, Int) -> Void
    let color: (Int) -> Binding<ThemeColor>
    let remove: (Int) -> Void
    @State private var dragged: Int?
    @State private var dragOffset: CGFloat = 0

    private static let handle: CGFloat = 20

    var body: some View {
        VStack(spacing: 4) {
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
            GeometryReader { proxy in
                let step =
                    colors.count > 1
                    ? (proxy.size.width - Self.handle) / CGFloat(colors.count - 1) : 0
                ZStack(alignment: .leading) {
                    ForEach(colors.indices, id: \.self) { index in
                        stop(index, step: step, width: proxy.size.width)
                    }
                }
                .coordinateSpace(.named(Self.space))
            }
            .frame(height: Self.handle)
            HStack {
                Label("Less activity", systemImage: "arrow.left")
                Spacer()
                Label("More activity", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, Self.handle / 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Left is less activity, right is more")
        }
        .padding(.vertical, 2)
    }

    private static let space = "gradient-stops"

    private func stop(_ index: Int, step: CGFloat, width: CGFloat) -> some View {
        let isSelected = index == selection
        let isDragged = index == dragged
        let base = CGFloat(index) * step
        let x = isDragged ? min(max(base + dragOffset, 0), width - Self.handle) : base
        return Circle()
            .fill(Color(colors[index]))
            .overlay {
                Circle().strokeBorder(
                    isSelected ? Color.primary : Color.primary.opacity(0.25),
                    lineWidth: isSelected ? 2.5 : 1)
            }
            .padding(isSelected || isDragged ? 0 : 3)
            .frame(width: Self.handle, height: Self.handle)
            .shadow(color: .black.opacity(isDragged ? 0.3 : 0), radius: 3)
            .contentShape(Circle())
            .popover(isPresented: popover(index), arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Color \(index + 1) of \(colors.count)").font(.headline)
                    InlineColorPicker(color: color(index))
                    Button("Remove Color", systemImage: "trash", role: .destructive) {
                        remove(index)
                    }
                    .disabled(colors.count <= ColorTheme.minColors)
                    .help(
                        colors.count <= ColorTheme.minColors
                            ? "A gradient needs at least \(ColorTheme.minColors) colors"
                            : "Remove this color from the gradient")
                }
                .padding(14)
            }
            .onTapGesture { open(index) }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        editing = nil
                        dragged = index
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let target =
                            step > 0
                            ? Int((CGFloat(index) + value.translation.width / step).rounded())
                            : index
                        dragged = nil
                        dragOffset = 0
                        select(index)
                        move(index, min(max(target, 0), colors.count - 1))
                    }
            )
            .padding(.leading, x)
            .zIndex(isDragged ? 1 : 0)
            .help("\(colors[index].hexString). Click to change, drag to reorder.")
            .accessibilityElement()
            .accessibilityLabel("Color \(index + 1) of \(colors.count), \(colors[index].hexString)")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { open(index) }
            .accessibilityAction(named: "Move left") {
                if index > 0 { move(index, index - 1) }
            }
            .accessibilityAction(named: "Move right") {
                if index + 1 < colors.count { move(index, index + 1) }
            }
    }

    private func open(_ index: Int) {
        releaseWindowFocus()
        select(index)
        editing = index
    }

    private func popover(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { editing == index },
            set: { if !$0, editing == index { editing = nil } })
    }
}

/// Title first, then the icon, so a right arrow points away from its text.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
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

    private static func points(_ counts: [Int], averages: Bool) -> [DashboardSnapshot.Point] {
        let start = CalendarDay(year: 2026, month: 1, day: 4)!
        return counts.indices.map { index in
            let window = counts[max(0, index - 6)...index]
            return DashboardSnapshot.Point(
                day: start.adding(days: index), count: counts[index],
                average: averages ? Double(window.reduce(0, +)) / Double(window.count) : nil,
                isIncomplete: false)
        }
    }
}
