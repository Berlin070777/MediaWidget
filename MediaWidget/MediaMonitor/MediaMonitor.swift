// MediaMonitor.swift
// MediaWidget
//
// Central class that monitors media playback state via MediaRemote,
// converts raw data into MediaInfo models, publishes changes via Combine,
// and shares data with the Widget extension via SharedDefaults.

import Foundation
import AppKit
import Combine

// MARK: - MediaMonitor

@MainActor
final class MediaMonitor: ObservableObject {

    // MARK: Published State

    /// The currently active media item, or `.empty` if nothing is playing.
    @Published var currentMedia: MediaInfo = .empty

    /// All detected media sources (for future multi-source switching).
    @Published var allSources: [MediaInfo] = []

    /// Whether the monitor is actively listening for changes.
    @Published var isMonitoring: Bool = false

    // MARK: Internal Properties

    /// Bridge to the MediaRemote private framework. `nil` if the framework could not be loaded.
    let bridge: MediaRemoteBridge?

    // MARK: Private Properties

    /// Timer that refreshes elapsed time while playback is active.
    private var refreshTimer: Timer?

    /// Shared UserDefaults for passing media data to the Widget extension.
    private let sharedDefaults = SharedDefaults()

    /// Notification center observers kept for cleanup.
    private var observers: [NSObjectProtocol] = []

    /// The interval (in seconds) at which elapsed time is refreshed during playback.
    private let refreshInterval: TimeInterval = 5.0

    // MARK: - Initializer

    init() {
        let loadedBridge = MediaRemoteBridge()
        if loadedBridge != nil {
            self.bridge = loadedBridge
        } else {
            self.bridge = nil
            print("[MediaMonitor] ⚠️ MediaRemoteBridge failed to load – media monitoring is unavailable.")
        }
    }

    deinit {
        let obs = observers
        for observer in obs {
            NotificationCenter.default.removeObserver(observer)
        }
        refreshTimer?.invalidate()
    }

    // MARK: - Public API

    /// Begin listening for media playback changes. Safe to call multiple times.
    func startMonitoring() {
        guard !isMonitoring else { return }
        guard let bridge else {
            print("[MediaMonitor] Cannot start monitoring – bridge is nil.")
            return
        }

        isMonitoring = true

        // 1. Ask MediaRemote to start sending notifications.
        bridge.registerForNotifications()

        // 2. Observe the three key notifications using the actual notification names from the bridge.
        let center = NotificationCenter.default

        let notificationNames = [
            bridge.nowPlayingInfoDidChangeNotification,
            bridge.nowPlayingApplicationDidChangeNotification,
            bridge.nowPlayingApplicationIsPlayingDidChangeNotification
        ]

        for name in notificationNames {
            let observer = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshNowPlaying()
                }
            }
            observers.append(observer)
        }

        // 3. Do the initial fetch.
        refreshNowPlaying()
    }

    /// Stop listening for media playback changes.
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()

        stopRefreshTimer()
    }

    /// Manually trigger a refresh of the now-playing state.
    func refreshNowPlaying() {
        guard let bridge else {
            currentMedia = .empty
            allSources = []
            return
        }

        // Fetch PID first, then info, then playing state
        bridge.getNowPlayingAppPID { [weak self] pid in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.bridge?.getNowPlayingInfo { [weak self] info in
                    Task { @MainActor [weak self] in
                        guard let self else { return }

                        self.bridge?.getIsPlaying { [weak self] isPlaying in
                            Task { @MainActor [weak self] in
                                guard let self else { return }

                                let mediaInfo: MediaInfo
                                if !info.isEmpty {
                                    mediaInfo = self.convertToMediaInfo(
                                        from: info,
                                        pid: pid,
                                        isPlaying: isPlaying
                                    )
                                } else {
                                    mediaInfo = .empty
                                }

                                self.currentMedia = mediaInfo
                                self.allSources = mediaInfo.isEmpty ? [] : [mediaInfo]

                                // Persist to shared defaults so the Widget can read it.
                                self.sharedDefaults.save(mediaInfo: mediaInfo)

                                // Manage the refresh timer based on playback state.
                                if mediaInfo.isPlaying {
                                    self.startRefreshTimer()
                                } else {
                                    self.stopRefreshTimer()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Timer Management

    /// Start a repeating timer that refreshes elapsed time while playback is active.
    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshNowPlaying()
            }
        }
        refreshTimer?.tolerance = 1.0
    }

    /// Invalidate the refresh timer.
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Data Conversion

    /// Convert raw MediaRemote info dictionary into a `MediaInfo` model.
    private func convertToMediaInfo(
        from info: [String: Any],
        pid: Int32,
        isPlaying: Bool
    ) -> MediaInfo {

        // --- Source Application ---
        var bundleIdentifier = ""
        var appName = "未知应用"

        if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
            bundleIdentifier = app.bundleIdentifier ?? ""
            appName = app.localizedName ?? app.bundleIdentifier ?? "未知应用"
        }

        let sourceAppInfo = SourceAppInfo.info(for: bundleIdentifier)

        // --- Media Metadata ---
        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String

        // --- Artwork ---
        let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

        // --- Playback Timing ---
        let duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0.0
        let elapsedTime = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0.0
        let playbackRate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0.0

        // --- Capabilities ---
        var capabilities: MediaCapabilities = [.canPlay, .canPause, .canNextTrack, .canPreviousTrack]
        if duration > 0 {
            capabilities.insert(.canSeek)
        }
        capabilities.insert(.canSetVolume)

        let now = Date()
        return MediaInfo(
            sourceID: bundleIdentifier,
            sourceName: sourceAppInfo.displayName,
            title: title.isEmpty ? "未知曲目" : title,
            artist: artist.isEmpty ? "未知艺术家" : artist,
            album: album,
            artworkData: artworkData,
            duration: duration,
            currentPosition: elapsedTime,
            playbackRate: isPlaying ? max(playbackRate, 1.0) : 0.0,
            volume: nil,
            capabilities: capabilities,
            lastUpdated: now,
            positionTimestamp: now
        )
    }
}
