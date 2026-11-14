import SwiftUI
import WidgetKit
import os

struct MediaWidgetEntry: TimelineEntry {
    let date: Date
    let mediaInfo: MediaInfo
    let showArtwork: Bool
}

struct MediaWidgetProvider: TimelineProvider {
    private static let logger = Logger(subsystem: "com.mediawidget.app", category: "WidgetTimeline")
    func placeholder(in context: Context) -> MediaWidgetEntry {
        MediaWidgetEntry(date: .now, mediaInfo: .empty, showArtwork: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (MediaWidgetEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MediaWidgetEntry>) -> Void) {
        let now = Date.now
        let entry = entry(at: now)
        Self.logger.info("Timeline size: \(String(describing: context.family), privacy: .public), artwork bytes: \(entry.mediaInfo.artworkData?.count ?? 0)")
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(300))))
    }

    private func entry(at date: Date) -> MediaWidgetEntry {
        let snapshot = SharedDefaults.shared.snapshot()
        return MediaWidgetEntry(date: date, mediaInfo: snapshot.flatMap { $0.isFresh ? $0.media : nil } ?? .empty,
                                showArtwork: snapshot?.showArtwork ?? true)
    }
}

struct MediaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Constants.widgetKind, provider: MediaWidgetProvider()) { entry in
            MediaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("媒体控制")
        .description("查看当前媒体，在通知中心播放、暂停或切换曲目。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
