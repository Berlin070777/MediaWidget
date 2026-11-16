import AppKit
import SwiftUI
import WidgetKit

enum WidgetSourceStyle {
    static func icon(for bundleID: String) -> String {
        switch bundleID {
        case Constants.KnownApp.neteaseMusic: "music.note"
        case Constants.KnownApp.bilibili: "play.tv.fill"
        case Constants.KnownApp.safari: "safari.fill"
        case Constants.KnownApp.chrome: "globe.americas.fill"
        case Constants.KnownApp.appleMusic: "music.mic"
        case Constants.KnownApp.spotify: "dot.radiowaves.left.and.right"
        default: "app.fill"
        }
    }

    static func shortName(_ name: String) -> String {
        name.components(separatedBy: " · ").first ?? name
    }
}

extension View {
    func widgetControlSurface<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        background(
            LinearGradient(colors: [tint?.opacity(0.30) ?? Color.primary.opacity(0.14),
                                    tint?.opacity(0.13) ?? Color.primary.opacity(0.06)],
                           startPoint: .top, endPoint: .bottom), in: shape
        )
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [Color.primary.opacity(0.20), Color.primary.opacity(0.06)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
        }
    }
}

struct ArtworkPalette {
    let top: Color
    let bottom: Color
    let accent: Color

    static func from(_ data: Data?) -> ArtworkPalette? {
        guard let data, let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 2
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        func sample(_ x: Int, _ y: Int) -> NSColor {
            let offset = (y * side + x) * 4
            return NSColor(deviceRed: CGFloat(pixels[offset]) / 255,
                           green: CGFloat(pixels[offset + 1]) / 255,
                           blue: CGFloat(pixels[offset + 2]) / 255, alpha: 1)
        }
        let topLeft = sample(0, 1), topRight = sample(1, 1)
        let bottomLeft = sample(0, 0), bottomRight = sample(1, 0)
        let top = blend(topLeft, topRight)
        let bottom = blend(bottomLeft, bottomRight)
        let accent = vivid(blend(top, bottom))
        return ArtworkPalette(top: Color(top), bottom: Color(bottom), accent: Color(accent))
    }

    private static func blend(_ lhs: NSColor, _ rhs: NSColor) -> NSColor {
        guard let left = lhs.usingColorSpace(.deviceRGB), let right = rhs.usingColorSpace(.deviceRGB) else { return lhs }
        return NSColor(deviceRed: (left.redComponent + right.redComponent) / 2,
                       green: (left.greenComponent + right.greenComponent) / 2,
                       blue: (left.blueComponent + right.blueComponent) / 2, alpha: 1)
    }

    private static func vivid(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(deviceHue: hue, saturation: max(saturation, 0.5),
                       brightness: min(max(brightness, 0.5), 0.82), alpha: 1)
    }
}
