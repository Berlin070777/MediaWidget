// MediaWidget.swift
// MediaWidgetExtension
//
// Widget definition with timeline provider for the media control widget.

import WidgetKit
import SwiftUI
import os

// MARK: - Timeline Entry

struct MediaWidgetEntry: TimelineEntry {
    let date: Date
    let mediaInfo: MediaInfo
}

// MARK: - Timeline Provider

struct MediaWidgetProvider: TimelineProvider {

    private let sharedDefaults = SharedDefaults()

    func placeholder(in context: Context) -> MediaWidgetEntry {
        MediaWidgetEntry(
            date: .now,
            mediaInfo: MediaInfo(
                sourceID: "com.apple.Music",
                sourceName: "Apple Music",
                title: "歌曲标题",
                artist: "艺术家",
                album: "专辑",
                artworkData: nil,
                duration: 240,
                currentPosition: 60,
                playbackRate: 1,
                volume: 0.5,
                capabilities: .standardPlayback,
                lastUpdated: .now,
                positionTimestamp: .now
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MediaWidgetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let info = sharedDefaults.loadMediaInfo() ?? .empty
        completion(MediaWidgetEntry(date: .now, mediaInfo: info))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MediaWidgetEntry>) -> Void) {
        let info = sharedDefaults.loadMediaInfo() ?? .empty
        // Visible in Console.app / `log stream` – makes debugging the widget much easier.
        Logger(subsystem: "com.mediawidget.app", category: "Widget")
            .info("Timeline entry: \(info.title, privacy: .public) / \(info.artist, privacy: .public) playing=\(info.isPlaying) artwork=\(info.artworkData?.count ?? 0)B")
        let entry = MediaWidgetEntry(date: .now, mediaInfo: info)

        // Schedule the next refresh based on playback state.
        let refreshInterval: TimeInterval = info.isPlaying ? 30 : 300
        let nextRefresh = Date.now.addingTimeInterval(refreshInterval)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

// MARK: - Widget Configuration

struct MediaWidget: Widget {
    let kind: String = Constants.WidgetKind.mediaControl

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MediaWidgetProvider()) { entry in
            MediaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("媒体控制")
        .description("显示当前播放的媒体信息和控制按钮")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview

#Preview("Medium", as: .systemMedium) {
    MediaWidget()
} timeline: {
    MediaWidgetEntry(
        date: .now,
        mediaInfo: MediaInfo(
            sourceID: "com.apple.Music",
            sourceName: "Apple Music",
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            artworkData: nil,
            duration: 354,
            currentPosition: 120,
            playbackRate: 1,
            volume: 0.7,
            capabilities: .all,
            lastUpdated: .now,
            positionTimestamp: .now
        )
    )
}

#Preview("Large", as: .systemLarge) {
    MediaWidget()
} timeline: {
    MediaWidgetEntry(
        date: .now,
        mediaInfo: .empty
    )
}
