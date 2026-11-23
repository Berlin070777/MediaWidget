import AppKit
import SwiftUI

extension View {
    @ViewBuilder
    func mediaGlassGroup(spacing: CGFloat) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    func mediaGlass<S: InsettableShape>(in shape: S, enabled: Bool = true) -> some View {
        modifier(MediaGlassSurface(shape: shape, enabled: enabled))
    }

    @ViewBuilder
    func mediaGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

private struct MediaGlassSurface<Surface: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: Surface
    let enabled: Bool

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if #available(macOS 26, *), !reduceTransparency {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background {
                    if reduceTransparency {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        shape.fill(.regularMaterial)
                    }
                }
                .overlay { shape.strokeBorder(.primary.opacity(0.10), lineWidth: 1).allowsHitTesting(false) }
        }
    }
}

struct MediaWindowBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(white: 0.105), Color(white: 0.042)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()
    }
}
