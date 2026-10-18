import AppKit
import SlopometerCore
import SwiftUI

/// A hue, saturation, and brightness picker drawn in place. The shared color panel opens
/// wherever AppKit last left it, often on another display; this one opens beside the
/// control that asked for it.
struct InlineColorPicker: View {
    @Binding var color: ThemeColor
    /// Kept apart from `color` so grays and black keep the hue someone was dragging.
    @State private var hue = 0.0
    @State private var saturation = 0.0
    @State private var brightness = 0.0
    @State private var hexText = ""

    private static let width: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SaturationBrightnessField(
                hue: hue, saturation: $saturation, brightness: $brightness, changed: apply
            )
            .frame(width: Self.width, height: 140)
            HueBar(hue: $hue, changed: apply)
                .frame(width: Self.width, height: 14)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(color))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.2))
                    }
                    .frame(width: 32, height: 22)
                    .accessibilityHidden(true)
                TextField("Hex", text: $hexText, prompt: Text("#RRGGBB"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .accessibilityLabel("Hex")
                    .onSubmit(applyHex)
            }
            .frame(width: Self.width)
        }
        .onAppear(perform: load)
        .onChange(of: color) { _, new in
            if new != current { load() }
            hexText = new.hexString
        }
    }

    private var current: ThemeColor {
        ThemeColor(hue: hue, saturation: saturation, brightness: brightness)
    }

    private func apply() {
        let updated = current
        if updated != color { color = updated }
    }

    private func applyHex() {
        if let parsed = ThemeColor(hexString: hexText) { color = parsed }
        hexText = color.hexString
    }

    private func load() {
        let (h, s, b) = color.hsb
        // Grays have no hue; keep the one already chosen.
        if s > 0.001, b > 0.001 { hue = h }
        saturation = s
        brightness = b
        hexText = color.hexString
    }
}

/// A swatch that opens `InlineColorPicker` in a popover beside itself.
struct ColorSwatchButton: View {
    let title: String
    @Binding var color: ThemeColor
    @State private var isPresented = false

    var body: some View {
        LabeledContent(title) {
            Button {
                releaseWindowFocus()
                isPresented.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(color))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.25))
                    }
                    .frame(width: 44, height: 20)
            }
            .buttonStyle(.plain)
            .help("Change \(title.lowercased()), \(color.hexString)")
            .accessibilityLabel("\(title), \(color.hexString)")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                InlineColorPicker(color: $color).padding(14)
            }
        }
    }
}

/// Saturation left to right, brightness bottom to top, for one hue.
private struct SaturationBrightnessField: View {
    let hue: Double
    @Binding var saturation: Double
    @Binding var brightness: Double
    let changed: () -> Void

    var body: some View {
        GeometryReader { proxy in
            field(size: proxy.size)
        }
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(Int(brightness * 100)) percent")
        .accessibilityAdjustableAction { direction in
            brightness = clamp(brightness + (direction == .increment ? 0.05 : -0.05))
            changed()
        }
    }

    private var colors: some View {
        ZStack {
            Color(hue: hue, saturation: 1, brightness: 1)
            LinearGradient(
                colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(
                colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(.rect(cornerRadius: 6))
    }

    private func field(size: CGSize) -> some View {
        // Typed one step at a time; mixed Double and CGFloat math in one modifier chain
        // is too slow for the type checker.
        let x: CGFloat = CGFloat(saturation) * size.width - 7
        let y: CGFloat = CGFloat(1 - brightness) * size.height - 7
        let marker = Circle()
            .strokeBorder(.white, lineWidth: 2)
            .background(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 3))
            .frame(width: 14, height: 14)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
        return
            colors
            .overlay(alignment: .topLeading) { marker }
            .contentShape(.rect)
            .gesture(drag(size: size))
    }

    private func drag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            saturation = clamp(Double(value.location.x / size.width))
            brightness = clamp(1 - Double(value.location.y / size.height))
            changed()
        }
    }
}

private struct HueBar: View {
    @Binding var hue: Double
    let changed: () -> Void

    private static let spectrum: [Color] = (0...6).map { step in
        Color(hue: Double(step) / 6, saturation: 1, brightness: 1)
    }

    var body: some View {
        GeometryReader { proxy in
            bar(size: proxy.size)
        }
        .accessibilityElement()
        .accessibilityLabel("Hue")
        .accessibilityValue("\(Int(hue * 360)) degrees")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1.0 / 36 : -1.0 / 36
            hue = (hue + step + 1).truncatingRemainder(dividingBy: 1)
            changed()
        }
    }

    private func bar(size: CGSize) -> some View {
        let knob: CGFloat = size.height + 4
        let x: CGFloat = CGFloat(hue) * size.width - knob / 2
        let marker = Circle()
            .fill(Color(hue: hue, saturation: 1, brightness: 1))
            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
            .shadow(color: .black.opacity(0.3), radius: 1)
            .frame(width: knob, height: knob)
            .offset(x: x)
            .allowsHitTesting(false)
        let gradient = LinearGradient(
            colors: Self.spectrum, startPoint: .leading, endPoint: .trailing)
        return Capsule()
            .fill(gradient)
            .overlay(alignment: .leading) { marker }
            .contentShape(.rect)
            .gesture(drag(width: size.width))
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            hue = min(clamp(Double(value.location.x / width)), 0.999)
            changed()
        }
    }
}

private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

extension ThemeColor {
    /// sRGB hue, saturation, and brightness, each 0 to 1.
    init(hue: Double, saturation: Double, brightness: Double) {
        let color = NSColor(
            colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        self.init(
            red: Double(color.redComponent), green: Double(color.greenComponent),
            blue: Double(color.blueComponent))
    }

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let color = NSColor(
            srgbRed: red, green: green, blue: blue, alpha: 1)
        var (h, s, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b))
    }
}
