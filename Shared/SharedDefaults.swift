// SharedDefaults.swift
// MediaWidget
//
// App Groups data sharing utility for communicating between the main app and widget extension.

import Foundation
import WidgetKit

/// A utility for reading and writing media information to the shared App Group container.
/// Used by both the main app (writer) and the widget extension (reader).
struct SharedDefaults: Sendable {

    // MARK: - Properties

    /// The shared `UserDefaults` suite backed by the App Group container.
    private let defaults: UserDefaults

    /// A JSON encoder configured for media info serialization.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    /// A JSON decoder configured for media info deserialization.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    // MARK: - Initialization

    /// Creates a `SharedDefaults` instance backed by the App Group's `UserDefaults`.
    /// Falls back to `.standard` if the App Group suite is unavailable.
    init() {
        if let suite = UserDefaults(suiteName: Constants.appGroupID) {
            self.defaults = suite
        } else {
            assertionFailure("Failed to create UserDefaults suite for App Group: \(Constants.appGroupID)")
            self.defaults = .standard
        }
    }

    // MARK: - Single MediaInfo (Current Now Playing)

    /// Saves the currently playing media info to the shared container.
    /// - Parameter mediaInfo: The media info to persist.
    func save(mediaInfo: MediaInfo) {
        do {
            let data = try Self.encoder.encode(mediaInfo)
            defaults.set(data, forKey: Constants.DefaultsKey.currentMediaInfo)
            defaults.set(Date().timeIntervalSince1970, forKey: Constants.DefaultsKey.lastUpdateTimestamp)
        } catch {
            assertionFailure("Failed to encode MediaInfo: \(error)")
        }
    }

    /// Loads the currently playing media info from the shared container.
    /// - Returns: The stored `MediaInfo`, or `nil` if none exists or decoding fails.
    func loadMediaInfo() -> MediaInfo? {
        guard let data = defaults.data(forKey: Constants.DefaultsKey.currentMediaInfo) else {
            return nil
        }
        do {
            return try Self.decoder.decode(MediaInfo.self, from: data)
        } catch {
            assertionFailure("Failed to decode MediaInfo: \(error)")
            return nil
        }
    }

    // MARK: - All Media Sources

    /// Saves the list of all active media sources to the shared container.
    /// - Parameter allSources: An array of `MediaInfo` representing each active source.
    func save(allSources: [MediaInfo]) {
        do {
            let data = try Self.encoder.encode(allSources)
            defaults.set(data, forKey: Constants.DefaultsKey.allMediaSources)
            defaults.set(Date().timeIntervalSince1970, forKey: Constants.DefaultsKey.lastUpdateTimestamp)
        } catch {
            assertionFailure("Failed to encode allSources: \(error)")
        }
    }

    /// Loads all active media sources from the shared container.
    /// - Returns: An array of `MediaInfo`, or an empty array if none exist or decoding fails.
    func loadAllSources() -> [MediaInfo] {
        guard let data = defaults.data(forKey: Constants.DefaultsKey.allMediaSources) else {
            return []
        }
        do {
            return try Self.decoder.decode([MediaInfo].self, from: data)
        } catch {
            assertionFailure("Failed to decode allSources: \(error)")
            return []
        }
    }

    // MARK: - Timestamps

    /// Returns the `Date` when the shared data was last updated, or `nil` if never.
    func lastUpdateTimestamp() -> Date? {
        let timestamp = defaults.double(forKey: Constants.DefaultsKey.lastUpdateTimestamp)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Whether the stored data is considered stale (older than the stale threshold).
    var isStale: Bool {
        guard let lastUpdate = lastUpdateTimestamp() else { return true }
        return Date().timeIntervalSince(lastUpdate) > Constants.Timing.staleThreshold
    }

    // MARK: - Widget Reload

    /// Requests that WidgetKit reload all timelines for the media widgets.
    /// Call this from the main app after updating shared data.
    func requestWidgetReload() {
        WidgetCenter.shared.reloadTimelines(ofKind: Constants.WidgetKind.nowPlaying)
        WidgetCenter.shared.reloadTimelines(ofKind: Constants.WidgetKind.mediaControl)
        WidgetCenter.shared.reloadTimelines(ofKind: Constants.WidgetKind.compactPlayer)
    }

    /// Saves the media info and immediately requests a widget timeline reload.
    /// Convenience method combining `save(mediaInfo:)` and `requestWidgetReload()`.
    /// - Parameter mediaInfo: The media info to persist.
    func saveAndReload(mediaInfo: MediaInfo) {
        save(mediaInfo: mediaInfo)
        requestWidgetReload()
    }

    /// Saves all sources and immediately requests a widget timeline reload.
    /// Convenience method combining `save(allSources:)` and `requestWidgetReload()`.
    /// - Parameter allSources: The source list to persist.
    func saveAndReload(allSources: [MediaInfo]) {
        save(allSources: allSources)
        requestWidgetReload()
    }

    // MARK: - Cleanup

    /// Removes all stored media data from the shared container.
    func clearAll() {
        defaults.removeObject(forKey: Constants.DefaultsKey.currentMediaInfo)
        defaults.removeObject(forKey: Constants.DefaultsKey.allMediaSources)
        defaults.removeObject(forKey: Constants.DefaultsKey.lastUpdateTimestamp)
    }
}
