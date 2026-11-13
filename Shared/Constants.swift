// Constants.swift
// MediaWidget
//
// App-wide constants shared between the main app and widget extension.

import Foundation

/// App-wide constants for the MediaWidget project.
enum Constants {

    // MARK: - App Group

    /// The App Group identifier used for sharing data between app and widget.
    static let appGroupID = "group.com.mediawidget.shared"

    // MARK: - Widget Kinds

    /// Widget kind identifiers.
    enum WidgetKind {
        static let nowPlaying = "NowPlayingWidget"
        static let mediaControl = "MediaControlWidget"
        static let compactPlayer = "CompactPlayerWidget"
    }

    // MARK: - UserDefaults Keys

    /// Keys used in the shared UserDefaults (App Group).
    enum DefaultsKey {
        static let currentMediaInfo = "currentMediaInfo"
        static let allMediaSources = "allMediaSources"
        static let lastUpdateTimestamp = "lastUpdateTimestamp"
        static let preferredSource = "preferredSource"
        static let widgetTheme = "widgetTheme"
        static let showArtwork = "showArtwork"
    }

    // MARK: - Notification Names

    /// Notification names for media state changes.
    enum Notifications {
        static let mediaInfoDidChange = Notification.Name("com.mediawidget.mediaInfoDidChange")
        static let playbackStateDidChange = Notification.Name("com.mediawidget.playbackStateDidChange")
        static let nowPlayingAppDidChange = Notification.Name("com.mediawidget.nowPlayingAppDidChange")
        static let widgetReloadRequested = Notification.Name("com.mediawidget.widgetReloadRequested")
        static let sourceListDidUpdate = Notification.Name("com.mediawidget.sourceListDidUpdate")
    }

    // MARK: - MediaRemote Commands

    /// MRMediaRemoteCommand raw values (UInt32) used with the private MediaRemote framework.
    enum MediaRemoteCommand {
        static let play: UInt32 = 0
        static let pause: UInt32 = 1
        static let togglePlayPause: UInt32 = 2
        static let stop: UInt32 = 3
        static let nextTrack: UInt32 = 4
        static let previousTrack: UInt32 = 5
        static let beginFastForward: UInt32 = 6
        static let endFastForward: UInt32 = 7
        static let beginRewind: UInt32 = 8
        static let endRewind: UInt32 = 9
        static let enableShuffle: UInt32 = 13
        static let disableShuffle: UInt32 = 14
        static let advanceRepeatMode: UInt32 = 15
    }

    // MARK: - Known Bundle Identifiers

    /// Bundle identifiers for known media source apps.
    enum KnownApp {
        static let neteaseMusic = "com.netease.163music"
        static let bilibili = "com.bilibili.app"
        static let safari = "com.apple.Safari"
        static let chrome = "com.google.Chrome"
        static let appleMusic = "com.apple.Music"
        static let spotify = "com.spotify.client"
        static let qqMusic = "com.tencent.QQMusicMac"
        static let iina = "com.colliderli.iina"
        static let vlc = "org.videolan.vlc"
    }

    // MARK: - Timing

    /// Timing constants for polling and updates.
    enum Timing {
        /// How frequently to poll for media info changes (in seconds).
        static let pollingInterval: TimeInterval = 1.0
        /// Widget timeline refresh interval (in minutes).
        static let widgetRefreshMinutes: Int = 5
        /// Maximum age (in seconds) before media info is considered stale.
        static let staleThreshold: TimeInterval = 30.0
    }
}
