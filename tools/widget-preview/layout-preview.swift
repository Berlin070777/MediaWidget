import AppKit
import SwiftUI
import WidgetKit

let outDir = URL(fileURLWithPath: "/tmp/mwpreview", isDirectory: true)

@MainActor
func wallpaper(size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    let gradient = NSGradient(colors: [
        NSColor(deviceRed: 0.16, green: 0.22, blue: 0.42, alpha: 1),
        NSColor(deviceRed: 0.45, green: 0.25, blue: 0.52, alpha: 1),
        NSColor(deviceRed: 0.85, green: 0.55, blue: 0.35, alpha: 1)
    ])
    gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 120)
    image.unlockFocus()
    return image
}

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
func render(entry: MediaWidgetEntry, family: WidgetFamily, size: CGSize, dark: Bool, name: String) {
    let view = MediaWidgetView(entry: entry, familyOverride: family)
        .environment(\.widgetRenderingMode, .fullColor)
        .padding(16)
        .frame(width: size.width, height: size.height)
        .background {
            ZStack {
                Image(nsImage: wallpaper(size: size)).resizable()
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .environment(\.colorScheme, dark ? .dark : .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let nsImage = renderer.nsImage, let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: NSBitmapImageRep.FileType.png,
                                       properties: [NSBitmapImageRep.PropertyKey: Any]()) else {
        print("FAILED \(name)")
        return
    }
    do {
        try png.write(to: outDir.appending(path: "\(name).png"))
        print("rendered \(name) \(Int(size.width))x\(Int(size.height))")
    } catch {
        print("WRITE FAILED \(name): \(error)")
    }
}

func check(_ condition: Bool, _ label: String) {
    print("\(condition ? "PASS" : "FAIL"): \(label)")
    if !condition { exit(1) }
}

@MainActor
func run() {
    let cover = coverArt()
    let sampleMedia = MediaInfo(
        sourceID: "preview:netease", bundleID: Constants.KnownApp.neteaseMusic,
        sourceName: "网易云音乐", title: "夜曲", artist: "周杰伦", album: "十一月的萧邦",
        artworkData: cover, duration: 227, currentPosition: 46,
        playbackState: .playing,
        capabilities: [.canPlay, .canPause, .canNextTrack, .canPreviousTrack, .canSeek]
    )
    let sampleSources = [
        WidgetSourceSummary(sourceID: sampleMedia.sourceID, bundleID: sampleMedia.bundleID,
                            name: sampleMedia.sourceName, title: sampleMedia.title, isPlaying: true),
        WidgetSourceSummary(sourceID: "preview:safari", bundleID: Constants.KnownApp.safari,
                            name: "Safari · B 站", title: "【官方 MV】Never Gonna Give You Up", isPlaying: false)
    ]
    let sample = MediaWidgetEntry(date: .now, mediaInfo: sampleMedia, showArtwork: true,
                                  sources: sampleSources, preferredSource: "")

    var bili = MediaInfo(
        sourceID: "safari:tab1", bundleID: Constants.KnownApp.safari,
        sourceName: "Safari · B 站", title: "【官方 MV】Never Gonna Give You Up - Rick Astley",
        artist: "索尼音乐中国", duration: 213, currentPosition: 58,
        playbackState: .playing, volume: 0.36,
        capabilities: [.canPlay, .canPause, .canSeek, .canSetVolume]
    )
    bili.artworkData = cover
    let biliEntry = MediaWidgetEntry(date: .now, mediaInfo: bili, showArtwork: true,
                                     sources: [
                                        WidgetSourceSummary(sourceID: "safari:tab1", bundleID: Constants.KnownApp.safari,
                                                            name: "Safari · B 站", title: bili.title, isPlaying: true),
                                        WidgetSourceSummary(sourceID: "preview:netease", bundleID: Constants.KnownApp.neteaseMusic,
                                                            name: "网易云音乐", title: "夜曲", isPlaying: false)
                                     ], preferredSource: "")

    let pinnedEntry = MediaWidgetEntry(date: .now, mediaInfo: sampleMedia, showArtwork: true,
                                       sources: sampleSources, preferredSource: "preview:netease")
    let emptyEntry = MediaWidgetEntry(date: .now, mediaInfo: .empty, showArtwork: true)
    let noArtEntry = MediaWidgetEntry(date: .now, mediaInfo: sampleMedia, showArtwork: false,
                                      sources: sampleSources, preferredSource: "")

    let small = CGSize(width: 160, height: 160)
    let medium = CGSize(width: 340, height: 160)
    let large = CGSize(width: 340, height: 340)

    for dark in [false, true] {
        let suffix = dark ? "dark" : "light"
        render(entry: sample, family: .systemSmall, size: small, dark: dark, name: "small-\(suffix)")
        render(entry: sample, family: .systemMedium, size: medium, dark: dark, name: "medium-\(suffix)")
        render(entry: sample, family: .systemLarge, size: large, dark: dark, name: "large-\(suffix)")
        render(entry: biliEntry, family: .systemMedium, size: medium, dark: dark, name: "medium-bili-\(suffix)")
        render(entry: pinnedEntry, family: .systemMedium, size: medium, dark: dark, name: "medium-pinned-\(suffix)")
        render(entry: emptyEntry, family: .systemSmall, size: small, dark: dark, name: "empty-small-\(suffix)")
        render(entry: emptyEntry, family: .systemMedium, size: medium, dark: dark, name: "empty-medium-\(suffix)")
        render(entry: noArtEntry, family: .systemMedium, size: medium, dark: dark, name: "medium-noart-\(suffix)")
    }


    let legacyJSON = """
    {"media":{"sourceID":"x","bundleID":"b","sourceName":"n","title":"t","playbackState":"playing","playbackRate":1,"lastUpdated":0,"capabilities":1},"writtenAt":0,"showArtwork":true}
    """
    let legacy = try? JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacyJSON.utf8))
    check(legacy != nil && legacy?.sources.isEmpty == true && legacy?.preferredSource == "", "legacy snapshot decodes with defaults")

    let modern = WidgetSnapshot(media: .empty, writtenAt: .now, showArtwork: true,
                                sources: [WidgetSourceSummary(sourceID: "s", bundleID: "b", name: "n", title: "t", isPlaying: true)],
                                preferredSource: "s")
    let roundTrip = try? JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(modern))
    check(roundTrip?.sources.count == 1 && roundTrip?.preferredSource == "s", "modern snapshot round-trips")

    let palette = ArtworkPalette.from(cover)
    check(palette != nil, "artwork palette extracted")
    print("ALL CHECKS DONE")
}

@main
struct LayoutPreviewMain {
    static func main() {
        MainActor.assumeIsolated { run() }
    }
}
