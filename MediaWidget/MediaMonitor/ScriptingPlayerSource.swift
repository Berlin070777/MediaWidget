// ScriptingPlayerSource.swift
// MediaWidget
//
// Fallback now-playing source that talks to scriptable players (Music, Spotify)
// through AppleScript.
//
// Why this exists: starting with recent macOS releases, `MRMediaRemoteGetNowPlayingInfo`
// returns nothing for third-party processes (verified on macOS 26 even with a
// team-signed app), so the private MediaRemote route alone is not enough.

import Foundation
import AppKit

// MARK: - ScriptingPlayerSource

/// Reads the current track from players that expose an AppleScript dictionary.
enum ScriptingPlayerSource {

    // MARK: Snapshot

    /// A single now-playing snapshot reported by a scriptable player.
    struct Snapshot: Sendable {
        let bundleID: String
        let title: String
        let artist: String
        let album: String?
        let duration: TimeInterval
        let position: TimeInterval
        let isPlaying: Bool
        let artworkURL: URL?

        /// Converts the snapshot into the shared `MediaInfo` model.
        func makeMediaInfo(artwork: Data?) -> MediaInfo {
            var capabilities: MediaCapabilities = [.canPlay, .canPause, .canNextTrack, .canPreviousTrack]
            if duration > 0 { capabilities.insert(.canSeek) }
            capabilities.insert(.canSetVolume)

            return MediaInfo(
                sourceID: bundleID,
                sourceName: SourceAppInfo.info(for: bundleID).displayName,
                title: title.isEmpty ? "未知曲目" : title,
                artist: artist.isEmpty ? "未知艺术家" : artist,
                album: album?.isEmpty == false ? album : nil,
                artworkData: artwork,
                duration: duration,
                currentPosition: position,
                playbackRate: isPlaying ? 1 : 0,
                volume: nil,
                capabilities: capabilities,
                lastUpdated: .now,
                positionTimestamp: .now
            )
        }
    }

    // MARK: Supported players

    /// A player we know how to query.
    private struct Player {
        let bundleID: String
        let appName: String
        /// Returns a tab-separated snapshot, or `nil` when the player has no track loaded.
        let script: String
        /// Whether the player reports durations in milliseconds.
        let durationInMilliseconds: Bool
        let hasArtworkURL: Bool
    }

    private static let players: [Player] = [
        Player(
            bundleID: "com.apple.Music",
            appName: "Music",
            script: """
            tell application "Music"
                set ps to (player state as string)
                if ps is "stopped" then return "stopped"
                set t to current track
                return ps & "\\t" & (name of t) & "\\t" & (artist of t) & "\\t" & (album of t) & "\\t" & (duration of t) & "\\t" & (player position)
            end tell
            """,
            durationInMilliseconds: false,
            hasArtworkURL: false
        ),
        Player(
            bundleID: "com.spotify.client",
            appName: "Spotify",
            script: """
            tell application "Spotify"
                set ps to (player state as string)
                if ps is "stopped" then return "stopped"
                set t to current track
                return ps & "\\t" & (name of t) & "\\t" & (artist of t) & "\\t" & (album of t) & "\\t" & (duration of t) & "\\t" & (player position) & "\\t" & (artwork url of t)
            end tell
            """,
            durationInMilliseconds: true,
            hasArtworkURL: true
        ),
    ]

    // MARK: Public API

    /// Returns the best snapshot across all supported players.
    ///
    /// A playing player always wins over a paused one; among equals the first
    /// supported player in declaration order is used.
    /// Must be called on the main thread (`NSAppleScript` is not reentrant).
    @MainActor
    static func currentSnapshot() -> Snapshot? {
        var pausedCandidate: Snapshot?

        for player in players {
            guard isRunning(bundleID: player.bundleID) else { continue }
            guard let snapshot = query(player) else { continue }

            if snapshot.isPlaying {
                return snapshot
            }
            if pausedCandidate == nil {
                pausedCandidate = snapshot
            }
        }
        return pausedCandidate
    }

    // MARK: Helpers

    /// Whether an app with the given bundle identifier is currently running.
    private static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Runs the player's AppleScript and parses the result.
    @MainActor
    private static func query(_ player: Player) -> Snapshot? {
        guard let script = NSAppleScript(source: player.script) else { return nil }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            NSLog("[ScriptingPlayerSource] %@ AppleScript error: %@",
                  player.appName, String(describing: errorInfo))
            return nil
        }

        guard let raw = result.stringValue, raw != "stopped" else { return nil }

        let fields = raw.components(separatedBy: "\t")
        guard fields.count >= 6 else { return nil }

        let state = fields[0]
        let durationRaw = Double(fields[4]) ?? 0
        let duration = player.durationInMilliseconds ? durationRaw / 1000 : durationRaw
        let position = Double(fields[5]) ?? 0

        var artworkURL: URL?
        if player.hasArtworkURL, fields.count >= 7, !fields[6].isEmpty {
            artworkURL = URL(string: fields[6])
        }

        return Snapshot(
            bundleID: player.bundleID,
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            duration: duration,
            position: position,
            isPlaying: state == "playing",
            artworkURL: artworkURL
        )
    }
}
