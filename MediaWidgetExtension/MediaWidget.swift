import AppKit
import SwiftUI
import WidgetKit
import os

struct MediaWidgetEntry: TimelineEntry {
    let date: Date
    let mediaInfo: MediaInfo
    let showArtwork: Bool
    var sources: [WidgetSourceSummary] = []
    var preferredSource: String = ""
}

struct MediaWidgetProvider: TimelineProvider {
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    private static let logger = Logger(subsystem: "com.mediawidget.app", category: "WidgetTimeline")
    func placeholder(in context: Context) -> MediaWidgetEntry {
        MediaWidgetEntry(date: .now, mediaInfo: .empty, showArtwork: true)
    }

    private func galleryEntry() -> MediaWidgetEntry {
        let media = MediaInfo(
            sourceID: "preview:netease", bundleID: Constants.KnownApp.neteaseMusic,
            sourceName: "网易云音乐", title: "示例曲目", artist: "示例歌手",
            artworkData: Self.previewArtwork, duration: 227, currentPosition: 46,
            playbackState: .playing,
            capabilities: [.canPlay, .canPause, .canNextTrack, .canPreviousTrack]
        )
        let sources = [
            WidgetSourceSummary(sourceID: media.sourceID, bundleID: media.bundleID,
                                name: media.sourceName, title: media.title, isPlaying: true),
            WidgetSourceSummary(sourceID: "preview:safari", bundleID: Constants.KnownApp.safari,
                                name: "Safari · B 站", title: "示例视频", isPlaying: false)
        ]
        return MediaWidgetEntry(date: .now, mediaInfo: media, showArtwork: true,
                                sources: sources, preferredSource: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (MediaWidgetEntry) -> Void) {
        completion(context.isPreview ? galleryEntry() : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MediaWidgetEntry>) -> Void) {
        let now = Date.now
        let entry = entry(at: now)
        Self.logger.info("Widget build \(Self.build, privacy: .public), timeline size: \(String(describing: context.family), privacy: .public), artwork bytes: \(entry.mediaInfo.artworkData?.count ?? 0), sources: \(entry.sources.count)")
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(300))))
    }

    private func entry(at date: Date) -> MediaWidgetEntry {
        let snapshot = SharedDefaults.shared.snapshot()
        let fresh = snapshot.flatMap { $0.isFresh ? $0 : nil }
        return MediaWidgetEntry(date: date, mediaInfo: fresh?.media ?? .empty,
                                showArtwork: snapshot?.showArtwork ?? true,
                                sources: fresh?.sources ?? [], preferredSource: fresh?.preferredSource ?? "")
    }

    private static let previewArtwork: Data? = {
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
    }()
}

struct MediaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Constants.widgetKind, provider: MediaWidgetProvider()) { entry in
            MediaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("媒体控制")
        .description("查看当前媒体，播放、暂停、切换曲目，并点按左上角胶囊切换播放源。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
