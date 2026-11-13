// NeteaseMusicSource.swift
// MediaWidget
//
// Fallback now-playing source for 网易云音乐 (com.netease.163music).
//
// NeteaseMusic 3.x publishes nothing readable to third parties on recent macOS
// versions: MediaRemote returns nothing for other processes and its Chromium UI
// exposes no accessibility tree. It does however keep a local SQLite play history,
// which is what this source reads:
//
//   ~/Library/Containers/com.netease.163music/Data/Documents/storage/sqlite_storage.sqlite3
//   → table `historyTracks` (playtime, jsonStr)  /  one row per played track

import Foundation
import SQLite3
import os
import AppKit

// MARK: - NeteaseMusicSource

/// Reads the currently playing NeteaseMusic track from its local play history.
enum NeteaseMusicSource {

    // MARK: Constants

    private static let bundleID = "com.netease.163music"
    private static let logger = Logger(subsystem: "com.mediawidget.app", category: "NeteaseMusic")

    /// SQLite database used by NeteaseMusic 3.x.
    static var databaseURL: URL? {
        guard let home = FileManager.default.homeDirectoryForCurrentUser as URL? else { return nil }
        let url = home
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Documents/storage", isDirectory: true)
            .appendingPathComponent("sqlite_storage.sqlite3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Snapshot

    /// A track read from NeteaseMusic's history.
    struct Track: Sendable {
        /// When playback of the track started.
        let startedAt: Date
        let title: String
        let artist: String
        let album: String?
        let duration: TimeInterval
        let artworkURL: URL?

        /// The song id, used as the artwork cache key.
        var cacheKey: String {
            artworkURL?.lastPathComponent ?? title
        }

        /// Best-effort playback state.
        ///
        /// NeteaseMusic only records the *start* of a track, so the elapsed time is
        /// derived from the timestamp. Once the track's duration has passed we assume
        /// playback has stopped or been paused.
        var isPlaying: Bool {
            let elapsed = Date().timeIntervalSince(startedAt)
            return elapsed >= 0 && elapsed < duration + 3
        }

        /// Elapsed time clamped to the track duration.
        var currentPosition: TimeInterval {
            max(0, min(Date().timeIntervalSince(startedAt), duration))
        }

        /// Converts the track into the shared `MediaInfo` model.
        func makeMediaInfo(artwork: Data?) -> MediaInfo {
            var capabilities: MediaCapabilities = [.canPlay, .canPause, .canNextTrack, .canPreviousTrack]
            if duration > 0 { capabilities.insert(.canSeek) }
            capabilities.insert(.canSetVolume)

            return MediaInfo(
                sourceID: bundleID,
                sourceName: "网易云音乐",
                title: title.isEmpty ? "未知曲目" : title,
                artist: artist.isEmpty ? "未知艺术家" : artist,
                album: album,
                artworkData: artwork,
                duration: duration,
                currentPosition: currentPosition,
                playbackRate: isPlaying ? 1 : 0,
                volume: nil,
                capabilities: capabilities,
                lastUpdated: .now,
                positionTimestamp: .now
            )
        }
    }

    // MARK: Public API

    /// Whether NeteaseMusic is running right now.
    static var isAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
            && databaseURL != nil
    }

    /// Reads the most recent track from NeteaseMusic's play history.
    ///
    /// Falls back to reading a temporary copy when the live database cannot be
    /// opened (e.g. an exclusive lock while NeteaseMusic is writing).
    static func currentTrack() -> Track? {
        guard let databaseURL else { return nil }

        var handle: OpaquePointer?
        let status = sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil)

        if status == SQLITE_OK, let handle {
            defer { sqlite3_close(handle) }
            if let track = readLatestTrack(from: handle) {
                return track
            }
        } else {
            logger.error("Cannot open NeteaseMusic database (status: \(status))")
            sqlite3_close(handle)
        }

        return currentTrackFromCopy()
    }

    /// Reads from a temporary copy of the database.
    static func currentTrackFromCopy() -> Track? {
        guard let databaseURL else { return nil }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("netease-copy-\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try FileManager.default.copyItem(at: databaseURL, to: temporary)
        } catch {
            logger.error("Cannot copy NeteaseMusic database: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(temporary.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else {
            sqlite3_close(handle)
            return nil
        }
        defer { sqlite3_close(handle) }
        return readLatestTrack(from: handle)
    }

    /// Shared row-decoding logic for a live or copied database.
    private static func readLatestTrack(from handle: OpaquePointer) -> Track? {
        let sql = "SELECT playtime, jsonStr FROM historyTracks ORDER BY playtime DESC LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let playtime = sqlite3_column_int64(statement, 0)
        guard let jsonPointer = sqlite3_column_text(statement, 1) else { return nil }
        let json = String(cString: jsonPointer)
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let artists = (object["artists"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String } ?? []
        let albumObject = object["album"] as? [String: Any]
        var artworkURL: URL?
        if let pictureString = albumObject?["picUrl"] as? String, !pictureString.isEmpty {
            artworkURL = URL(string: pictureString.replacingOccurrences(of: "http://", with: "https://"))
        }

        return Track(
            startedAt: Date(timeIntervalSince1970: TimeInterval(playtime) / 1000),
            title: object["name"] as? String ?? "",
            artist: artists.joined(separator: " / "),
            album: (albumObject?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            duration: ((object["duration"] as? NSNumber)?.doubleValue ?? 0) / 1000,
            artworkURL: artworkURL
        )
    }
}

// MARK: - ArtworkCache

/// Disk-backed cache for remote artwork, so the widget and the panel agree and we
/// do not re-download on every refresh.
enum ArtworkCache {

    private static let logger = Logger(subsystem: "com.mediawidget.app", category: "ArtworkCache")

    private static var directory: URL {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("MediaWidget/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Returns cached artwork data for the key, if present.
    static func cachedData(for key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    /// Downloads artwork in the background and calls back on the main queue.
    static func load(url: URL, key: String, completion: @escaping @Sendable (Data?) -> Void) {
        let fileURL = fileURL(for: key)

        if let data = try? Data(contentsOf: fileURL) {
            DispatchQueue.main.async { completion(data) }
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                logger.error("Artwork download failed: \(error.localizedDescription, privacy: .public)")
            }
            if let data, !data.isEmpty {
                try? data.write(to: fileURL, options: .atomic)
            }
            DispatchQueue.main.async { completion(data) }
        }.resume()
    }

    private static func fileURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).jpg")
    }
}
