import AppKit
import SwiftUI
import WidgetKit
import CoreGraphics

let outDir = URL(fileURLWithPath: "/tmp/mwpreview", isDirectory: true)

@MainActor
func coverArt() -> Data? {
    let size = CGSize(width: 96, height: 96)
    let image = NSImage(size: size)
    image.lockFocus()
    let gradient = NSGradient(colors: [
        NSColor(deviceRed: 0.30, green: 0.14, blue: 0.58, alpha: 1),
        NSColor(deviceRed: 0.82, green: 0.24, blue: 0.54, alpha: 1)
    ])
    gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 135)
    if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white])) {
        let side: CGFloat = 40
        note.draw(in: NSRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side))
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
}

@MainActor
@available(macOS 26, *)
func captureGlass(entry: MediaWidgetEntry, family: WidgetFamily, size: CGSize, dark: Bool, name: String) {
    let view = MediaWidgetView(entry: entry, familyOverride: family)
        .environment(\.widgetRenderingMode, .fullColor)
        .environment(\.colorScheme, dark ? .dark : .light)
        .padding(16)
        .frame(width: size.width, height: size.height)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: size.width, height: size.height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.hasShadow = true
    window.level = .floating
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    host.autoresizingMask = [.width, .height]
    window.contentView = host
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.7))
    var image = CGWindowListCreateImage(.null, [.optionIncludingWindow],
                                        CGWindowID(window.windowNumber),
                                        [.boundsIgnoreFraming, .bestResolution])
    if image == nil, let content = window.contentView {
        let bounds = content.bounds
        if let rep = content.bitmapImageRepForCachingDisplay(in: bounds) {
            content.cacheDisplay(in: bounds, to: rep)
            image = rep.cgImage
        }
    }
    window.orderOut(nil)
    guard let image else {
        print("CAPTURE NIL \(name) — likely screen-capture permission")
        return
    }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: NSBitmapImageRep.FileType.png,
                                         properties: [NSBitmapImageRep.PropertyKey: Any]()) else {
        print("ENCODE FAIL \(name)")
        return
    }
    try? png.write(to: outDir.appending(path: "glass-\(name).png"))
    print("captured glass-\(name) \(image.width)x\(image.height)")
}

@MainActor
func run() {
    NSApplication.shared.setActivationPolicy(.accessory)
    let cover = coverArt()
    let media = MediaInfo(
        sourceID: "preview:netease", bundleID: Constants.KnownApp.neteaseMusic,
        sourceName: "网易云音乐", title: "夜曲", artist: "周杰伦", album: "十一月的萧邦",
        artworkData: cover, duration: 227, currentPosition: 46,
        playbackState: .playing,
        capabilities: [.canPlay, .canPause, .canNextTrack, .canPreviousTrack]
    )
    let sources = [
        WidgetSourceSummary(sourceID: media.sourceID, bundleID: media.bundleID,
                            name: media.sourceName, title: media.title, isPlaying: true),
        WidgetSourceSummary(sourceID: "preview:safari", bundleID: Constants.KnownApp.safari,
                            name: "Safari · B 站", title: "Never Gonna Give You Up", isPlaying: false)
    ]
    let entry = MediaWidgetEntry(date: .now, mediaInfo: media, showArtwork: true,
                                 sources: sources, preferredSource: "")
    if #available(macOS 26, *) {
        captureGlass(entry: entry, family: .systemMedium, size: CGSize(width: 340, height: 160), dark: false, name: "medium-light")
        captureGlass(entry: entry, family: .systemSmall, size: CGSize(width: 160, height: 160), dark: false, name: "small-light")
        captureGlass(entry: entry, family: .systemLarge, size: CGSize(width: 340, height: 340), dark: true, name: "large-dark")
    }
    print("GLASS CAPTURE DONE")
}

@main
struct GlassMain {
    static func main() {
        MainActor.assumeIsolated { run() }
    }
}