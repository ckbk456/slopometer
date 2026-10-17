import SwiftUI

// Liquid Glass for the app window on macOS 26 and later. CI builds with an SDK that
// has no glass API (Xcode 16.4), so every use is behind both a compiler check and an
// availability check, and earlier systems keep the previous appearance. Standard
// controls (Form, segmented pickers, tabs) adopt the new design from the SDK by
// themselves; these helpers cover the app's own cards, badges, and small buttons.

extension View {
    /// A content card: glass on macOS 26+, a quaternary fill before.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                glassEffect(.regular, in: shape)
            } else {
                background(.quaternary.opacity(0.5), in: shape)
            }
        #else
            background(.quaternary.opacity(0.5), in: shape)
        #endif
    }

    /// A small label in a capsule, tinted with `tint`.
    @ViewBuilder
    func glassCapsule(tint: Color) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                glassEffect(.regular.tint(tint.opacity(0.2)), in: Capsule())
            } else {
                background(tint.opacity(0.14), in: Capsule())
            }
        #else
            background(tint.opacity(0.14), in: Capsule())
        #endif
    }

    /// Small icon buttons (refresh, help). Borderless before macOS 26. Do not use inside
    /// a glass card: glass is not stacked on glass.
    @ViewBuilder
    func glassIconButtonStyle() -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                buttonStyle(.glass).buttonBorderShape(.circle)
            } else {
                buttonStyle(.borderless)
            }
        #else
            buttonStyle(.borderless)
        #endif
    }
}

/// Lets neighboring glass elements render and blend together; a plain container before
/// macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: spacing) { content() }
            } else {
                content()
            }
        #else
            content()
        #endif
    }
}
