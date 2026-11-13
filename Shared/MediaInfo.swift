// MediaInfo.swift
// MediaWidget
//
// Core data model for media information. Codable for App Groups sharing.

import Foundation

// MARK: - MediaCapabilities

/// An OptionSet describing what media controls are available for the current source.
struct MediaCapabilities: OptionSet, Codable, Sendable, Hashable {
    let rawValue: UInt

    static let canPlay            = MediaCapabilities(rawValue: 1 << 0)
    static let canPause           = MediaCapabilities(rawValue: 1 << 1)
    static let canNextTrack       = MediaCapabilities(rawValue: 1 << 2)
    static let canPreviousTrack   = MediaCapabilities(rawValue: 1 << 3)
    static let canSeek            = MediaCapabilities(rawValue: 1 << 4)
    static let canSetVolume       = MediaCapabilities(rawValue: 1 << 5)

    /// Convenience: can toggle play/pause
    var canTogglePlayPause: Bool {
        contains(.canPlay) || contains(.canPause)
    }

    /// Convenience: can skip to next
    var canSkipNext: Bool {
        contains(.canNextTrack)
    }

    /// Convenience: can skip to previous
    var canSkipPrevious: Bool {
        contains(.canPreviousTrack)
    }

    /// A typical set of capabilities for a standard music player.
    static let standardPlayback: MediaCapabilities = [.canPlay, .canPause, .canNextTrack, .canPreviousTrack, .canSeek]

    /// All capabilities enabled.
    static let all: MediaCapabilities = [.canPlay, .canPause, .canNextTrack, .canPreviousTrack, .canSeek, .canSetVolume]
}

// MARK: - SourceAppInfo

/// Maps bundle identifiers to human-readable display names and SF Symbol icon names.
struct SourceAppInfo: Codable, Sendable, Hashable {
    /// The bundle identifier of the source app.
    let bundleIdentifier: String
    /// Human-readable display name for the source app.
    let displayName: String
    /// SF Symbol name representing the source app.
    let symbolName: String

    /// Returns the `SourceAppInfo` for a given bundle identifier.
    static func info(for bundleID: String) -> SourceAppInfo {
        switch bundleID {
        case Constants.KnownApp.neteaseMusic:
            return SourceAppInfo(bundleIdentifier: bundleID, displayName: "网易云音乐", symbolName: "music.note")
        case Constants.KnownApp.bilibili:
            return SourceAppInfo(bundleIdentifier: bundleID, displayName: "哔哩哔哩", symbolName: "play.rectangle")
        case Constants.KnownApp.safari:
            return SourceAppInfo(bundleIdentifier: bundleID, displayName: "Safari", symbolName: "safari")
        case Constants.KnownApp.chrome:
            return SourceAppInfo(bundleIdentifier: bundleID, displayName: "Chrome", symbolName: "globe")
        case Constants.KnownApp.appleMusic:
            return SourceAppInfo(bundleIdentifier: bundleID, displayName: "Apple Music", symbolName: "music.note.list")
        case Constants.KnownApp.spotify:
            return SourceAppInfo(bundleIdentifier: bundleID, displayName: "Spotify", symbolName: "music.note")
        case Constants.KnownApp.qqMusic:
            return SourceAppInfo(bundleIdentifier: bundleID, displayName: "QQ音乐", symbolName: "music.quarternote.3")
        case Constants.KnownApp.iina:
            return SourceAppInfo(bundleIdentifier: bundleID, displayName: "IINA", symbolName: "play.rectangle.fill")
        case Constants.KnownApp.vlc:
            return SourceAppInfo(bundleIdentifier: bundleID, displayName: "VLC", symbolName: "play.circle")
        default:
            return SourceAppInfo(bundleIdentifier: bundleID, displayName: bundleID, symbolName: "speaker.wave.2")
        }
    }
}

// MARK: - MediaInfo

/// The core data model representing the current media playback state.
/// Designed to be serialized via `Codable` and shared through App Groups.
struct MediaInfo: Codable, Sendable, Hashable, Identifiable {

    // MARK: Identification

    /// Unique identifier derived from `sourceID`.
    var id: String { sourceID }

    /// The bundle identifier of the source app (e.g., "com.netease.163music").
    var sourceID: String

    /// Human-readable name of the source app (e.g., "网易云音乐").
    var sourceName: String

    // MARK: Track Metadata

    /// The title of the currently playing track or video.
    var title: String

    /// The artist or author of the current track.
    var artist: String

    /// The album name, if available.
    var album: String?

    /// Raw image data (JPEG or PNG) for the track's artwork.
    var artworkData: Data?

    // MARK: Playback State

    /// Total duration of the current track in seconds.
    var duration: TimeInterval

    /// The playback position (in seconds) at the time it was last recorded.
    var currentPosition: TimeInterval

    /// The playback rate. 0 means paused, 1 means normal speed playback.
    var playbackRate: Double

    /// Whether the track is currently playing, derived from `playbackRate`.
    var isPlaying: Bool {
        playbackRate > 0
    }

    /// Whether this info represents an empty/no-media state.
    var isEmpty: Bool {
        sourceID.isEmpty
    }

    /// The system volume from the source, if available. Range: 0.0–1.0.
    var volume: Float?

    /// The set of media controls supported by the current source.
    var capabilities: MediaCapabilities

    // MARK: Timestamps

    /// When this `MediaInfo` was last updated.
    var lastUpdated: Date

    /// When `currentPosition` was last recorded. Used for interpolation.
    var positionTimestamp: Date

    // MARK: - Computed Properties

    /// Estimates the current playback position by interpolating from `currentPosition`
    /// using `playbackRate` and the time elapsed since `positionTimestamp`.
    /// Clamps the result to `[0, duration]`.
    var estimatedCurrentPosition: TimeInterval {
        guard isPlaying else {
            return min(currentPosition, duration)
        }
        let elapsed = Date().timeIntervalSince(positionTimestamp)
        let estimated = currentPosition + elapsed * playbackRate
        return max(0, min(estimated, duration))
    }

    /// The fractional progress through the track, from 0.0 to 1.0.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return estimatedCurrentPosition / duration
    }

    /// Returns the `SourceAppInfo` for this media info's `sourceID`.
    var sourceAppInfo: SourceAppInfo {
        SourceAppInfo.info(for: sourceID)
    }

    /// Whether this media info is considered stale (not recently updated).
    var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > Constants.Timing.staleThreshold
    }

    // MARK: - Static Properties

    /// An empty default `MediaInfo` representing no media playing.
    static let empty = MediaInfo(
        sourceID: "",
        sourceName: "",
        title: "未在播放",
        artist: "—",
        album: nil,
        artworkData: nil,
        duration: 0,
        currentPosition: 0,
        playbackRate: 0,
        volume: nil,
        capabilities: [],
        lastUpdated: .distantPast,
        positionTimestamp: .distantPast
    )
}

// MARK: - Formatting Helpers

extension MediaInfo {
    /// Formats a time interval as "m:ss" or "h:mm:ss".
    static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// The current position formatted as a human-readable string.
    var formattedCurrentPosition: String {
        MediaInfo.formatTime(estimatedCurrentPosition)
    }

    /// The total duration formatted as a human-readable string.
    var formattedDuration: String {
        MediaInfo.formatTime(duration)
    }
}
