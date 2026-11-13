// SharedDefaults.swift
// MediaWidget
//
// App Groups data sharing utility for communicating between the main app and widget extension.
//
// Storage strategy (in priority order):
//   1. App Group `UserDefaults` suite — requires a valid provisioning profile that
//      includes `group.com.mediawidget.shared`.
//   2. Fallback: a plain plist in `~/Library/Application Support/MediaWidget/`.
//      Both the app and the widget are non-sandboxed (`app-sandbox = false`), so this
//      works even with ad-hoc signing during local development.
//
// The fallback exists so the project runs out-of-the-box without a paid developer
// account; ship with App Groups enabled for distribution.

import Foundation
import os

#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - SharedDefaults

/// A utility for reading and writing media information to a container shared
/// between the main app (writer) and the widget extension (reader).
final class SharedDefaults: @unchecked Sendable {

    // MARK: - Backend

    /// Where the shared data physically lives.
    private enum Backend {
        /// `UserDefaults` backed by an App Group container.
        case suite(UserDefaults)
        /// A shared plist file outside of any container (development fallback).
        case file(URL)
    }

    // MARK: - Properties

    private static let logger = Logger(subsystem: "com.mediawidget.app", category: "SharedDefaults")

    private let backend: Backend
    private let lock = NSLock()

    /// Path of the fallback plist, used when no App Group is available.
    ///
    /// Two candidates are tried in order, and the first writable one wins:
    ///
    /// 1. The widget extension's sandbox container – the app is not sandboxed, so it
    ///    may create and write there, while the sandboxed widget can read its own
    ///    container. This gives cross-process sharing without an App Group.
    /// 2. The plain `~/Library/Application Support/MediaWidget` directory, which is
    ///    what the sandboxed widget sees as *its* Application Support.
    static var fallbackFileURL: URL {
        let fileName = "SharedState.plist"

        for directory in fallbackDirectories {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                return directory.appendingPathComponent(fileName)
            } catch {
                continue
            }
        }

        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
    }

    /// Candidate directories for the shared state file, most preferred first.
    private static var fallbackDirectories: [URL] {
        var candidates: [URL] = []

        // 1. Widget sandbox container (visible to a non-sandboxed writer).
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(Constants.widgetBundleID, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support/MediaWidget", isDirectory: true)
        candidates.append(container)

        // 2. Our own Application Support (the sandbox container when sandboxed).
        if let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first {
            candidates.append(base.appendingPathComponent("MediaWidget", isDirectory: true))
        }

        return candidates
    }

    // MARK: - Coders

    /// A JSON encoder configured for media info serialization.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    /// A JSON decoder configured for media info deserialization.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    // MARK: - Initialization

    /// Creates a `SharedDefaults` instance.
    ///
    /// Prefers the App Group suite; falls back to a shared plist file when the
    /// entitlement is not granted (e.g. ad-hoc signed builds without a team).
    init(appGroupID: String = Constants.appGroupID) {
        if let suite = UserDefaults(suiteName: appGroupID),
           Self.suiteHasContainer(appGroupID: appGroupID) {
            self.backend = .suite(suite)
            Self.logger.info("Shared storage: App Group suite \(appGroupID, privacy: .public)")
        } else {
            let url = Self.fallbackFileURL
            self.backend = .file(url)
            Self.logger.warning("App Group unavailable – falling back to shared file at \(url.path, privacy: .public)")
        }
    }

    /// Whether the current process really got a usable App Group container.
    /// `UserDefaults(suiteName:)` may return a suite object even when the
    /// entitlement is missing, which would silently write to a per-app domain.
    private static func suiteHasContainer(appGroupID: String) -> Bool {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return false
        }
        return FileManager.default.isWritableFile(atPath: container.path)
    }

    // MARK: - Low-level storage

    private func setData(_ data: Data?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        switch backend {
        case .suite(let defaults):
            if let data {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        case .file(let url):
            var dict = Self.readFile(url)
            if let data {
                dict[key] = data
            } else {
                dict.removeValue(forKey: key)
            }
            Self.writeFile(url, dict)
        }
    }

    private func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        switch backend {
        case .suite(let defaults):
            return defaults.data(forKey: key)
        case .file(let url):
            return Self.readFile(url)[key] as? Data
        }
    }

    private func setDouble(_ value: Double, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        switch backend {
        case .suite(let defaults):
            defaults.set(value, forKey: key)
        case .file(let url):
            var dict = Self.readFile(url)
            dict[key] = value
            Self.writeFile(url, dict)
        }
    }

    private func double(forKey key: String) -> Double {
        lock.lock()
        defer { lock.unlock() }

        switch backend {
        case .suite(let defaults):
            return defaults.double(forKey: key)
        case .file(let url):
            return (Self.readFile(url)[key] as? Double) ?? 0
        }
    }

    private func removeObject(forKey key: String) {
        setData(nil, forKey: key)
    }

    // MARK: - File backend helpers

    private static func readFile(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any]
        else {
            return [:]
        }
        return dict
    }

    private static func writeFile(_ url: URL, _ dict: [String: Any]) {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .binary,
            options: 0
        ) else {
            logger.error("Failed to serialize shared state")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to write shared state: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Single MediaInfo (Current Now Playing)

    /// Saves the currently playing media info to the shared container.
    /// - Parameter mediaInfo: The media info to persist.
    func save(mediaInfo: MediaInfo) {
        do {
            let data = try Self.makeEncoder().encode(mediaInfo)
            setData(data, forKey: Constants.DefaultsKey.currentMediaInfo)
            setDouble(Date().timeIntervalSince1970, forKey: Constants.DefaultsKey.lastUpdateTimestamp)
        } catch {
            Self.logger.error("Failed to encode MediaInfo: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Loads the currently playing media info from the shared container.
    /// - Returns: The stored `MediaInfo`, or `nil` if none exists or decoding fails.
    func loadMediaInfo() -> MediaInfo? {
        guard let data = data(forKey: Constants.DefaultsKey.currentMediaInfo) else {
            return nil
        }
        do {
            return try Self.makeDecoder().decode(MediaInfo.self, from: data)
        } catch {
            Self.logger.error("Failed to decode MediaInfo: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - All Media Sources

    /// Saves the list of all active media sources to the shared container.
    /// - Parameter allSources: An array of `MediaInfo` representing each active source.
    func save(allSources: [MediaInfo]) {
        do {
            let data = try Self.makeEncoder().encode(allSources)
            setData(data, forKey: Constants.DefaultsKey.allMediaSources)
            setDouble(Date().timeIntervalSince1970, forKey: Constants.DefaultsKey.lastUpdateTimestamp)
        } catch {
            Self.logger.error("Failed to encode allSources: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Loads all active media sources from the shared container.
    /// - Returns: An array of `MediaInfo`, or an empty array if none exist or decoding fails.
    func loadAllSources() -> [MediaInfo] {
        guard let data = data(forKey: Constants.DefaultsKey.allMediaSources) else {
            return []
        }
        do {
            return try Self.makeDecoder().decode([MediaInfo].self, from: data)
        } catch {
            Self.logger.error("Failed to decode allSources: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Timestamps

    /// Returns the `Date` when the shared data was last updated, or `nil` if never.
    func lastUpdateTimestamp() -> Date? {
        let timestamp = double(forKey: Constants.DefaultsKey.lastUpdateTimestamp)
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
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: Constants.WidgetKind.nowPlaying)
        WidgetCenter.shared.reloadTimelines(ofKind: Constants.WidgetKind.mediaControl)
        WidgetCenter.shared.reloadTimelines(ofKind: Constants.WidgetKind.compactPlayer)
        #endif
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
        removeObject(forKey: Constants.DefaultsKey.currentMediaInfo)
        removeObject(forKey: Constants.DefaultsKey.allMediaSources)
        removeObject(forKey: Constants.DefaultsKey.lastUpdateTimestamp)
    }
}

// MARK: - Shared Instance

extension SharedDefaults {
    /// A process-wide shared instance.
    static let shared = SharedDefaults()
}
