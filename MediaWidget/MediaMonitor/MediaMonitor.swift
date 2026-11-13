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

    // MARK: Shared Instance

    /// The single monitor shared by the menu bar UI, the floating panel and the app delegate.
    /// Creating several instances would register duplicate MediaRemote observers.
    static let shared = MediaMonitor()

    // MARK: Published State

    /// The currently active media item, or `.empty` if nothing is playing.
    @Published var currentMedia: MediaInfo = .empty

    /// All detected media sources (for future multi-source switching).
    @Published var allSources: [MediaInfo] = []

    /// Whether the monitor is actively listening for changes.
    @Published var isMonitoring: Bool = false

    /// Human-readable label of the source that produced the current snapshot.
    /// MediaRemote is unusable on recent macOS releases, so this tells the user
    /// which fallback is in charge.
    @Published var activeSourceLabel: String = "—"

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

    /// Last time the shared store was written, used to throttle widget reloads.
    private var lastSharedWrite: Date = .distantPast

    /// Whether demo mode is active. When enabled, the UI shows a sample track so
    /// the interface can be inspected without a real player running.
    /// Toggle with: `defaults write com.mediawidget.app demoMode -bool YES`
    var isDemoModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "demoMode")
    }

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

    // No `deinit`: `MediaMonitor` is `@MainActor`-isolated and lives for the whole app
    // lifetime. Notification observers and the refresh timer are torn down by
    // `stopMonitoring()`, which is called from `shutdown()` on app termination.

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

        // 3. MediaRemote no longer delivers now-playing notifications on recent macOS
        //    releases, so poll the fallback sources on a timer as well.
        startRefreshTimer()

        // 4. Do the initial fetch.
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
            // No MediaRemote at all – go straight to the per-app fallback sources.
            resolveFallback()
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

                                var mediaInfo: MediaInfo
                                if !info.isEmpty {
                                    mediaInfo = self.convertToMediaInfo(
                                        from: info,
                                        pid: pid,
                                        isPlaying: isPlaying
                                    )
                                } else {
                                    mediaInfo = .empty
                                }

                                // Demo mode overrides real state so the UI can be previewed.
                                if self.isDemoModeEnabled {
                                    self.applyMediaInfo(.demo)
                                    return
                                }

                                if mediaInfo.isEmpty {
                                    // MediaRemote returned nothing – fall back to the
                                    // per-app sources (AppleScript players / NeteaseMusic).
                                    self.resolveFallback()
                                } else {
                                    self.activeSourceLabel = "MediaRemote"
                                    self.applyMediaInfo(mediaInfo)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Fallback Sources

    /// Resolves now-playing state from non-MediaRemote sources.
    ///
    /// Priority: a *playing* source always wins over a paused one, so a paused
    /// Music.app never masks a track that NeteaseMusic is actually playing.
    private func resolveFallback() {
        // AppleScript must run on the main thread; the SQLite read is cheap enough
        // to do inline.
        let scripting = ScriptingPlayerSource.currentSnapshot()
        let netease = NeteaseMusicSource.isAppRunning ? NeteaseMusicSource.currentTrack() : nil

        if let scripting, scripting.isPlaying {
            applyScripting(scripting)
        } else if let netease, netease.isPlaying {
            applyNetease(netease)
        } else if let scripting {
            applyScripting(scripting)
        } else if let netease {
            applyNetease(netease)
        } else {
            activeSourceLabel = "—"
            applyMediaInfo(.empty)
        }
    }

    /// Applies a snapshot from a scriptable player, fetching artwork when needed.
    private func applyScripting(_ snapshot: ScriptingPlayerSource.Snapshot) {
        activeSourceLabel = "AppleScript · Music / Spotify"
        let artworkKey = snapshot.artworkURL?.lastPathComponent
        let artwork = artworkKey.flatMap { ArtworkCache.cachedData(for: $0) }
        applyMediaInfo(snapshot.makeMediaInfo(artwork: artwork))

        guard artwork == nil, let artworkKey, let url = snapshot.artworkURL else { return }
        ArtworkCache.load(url: url, key: artworkKey) { [weak self] data in
            guard data != nil else { return }
            Task { @MainActor [weak self] in
                self?.refreshNowPlaying()
            }
        }
    }

    /// Applies a track read from NeteaseMusic's history, fetching artwork when needed.
    private func applyNetease(_ track: NeteaseMusicSource.Track) {
        activeSourceLabel = "网易云音乐 · 本地播放记录"
        let artwork = ArtworkCache.cachedData(for: track.cacheKey)
        applyMediaInfo(track.makeMediaInfo(artwork: artwork))

        guard artwork == nil, let url = track.artworkURL else { return }
        ArtworkCache.load(url: url, key: track.cacheKey) { [weak self] data in
            guard data != nil else { return }
            Task { @MainActor [weak self] in
                self?.refreshNowPlaying()
            }
        }
    }

    /// Applies a media snapshot to the published state and, when something
    /// *meaningful* changed, to the shared store.
    ///
    /// `MediaInfo` carries `lastUpdated` / `positionTimestamp`, which change on every
    /// poll. Writing and reloading the widget on those alone would trigger a widget
    /// reload every few seconds, so only real changes (track, source, play state,
    /// artwork) hit the disk and WidgetKit.
    private func applyMediaInfo(_ mediaInfo: MediaInfo) {
        let previous = currentMedia
        let isFirstWrite = previous.isEmpty && !mediaInfo.isEmpty
        let significantChange = isFirstWrite
            || previous.sourceID != mediaInfo.sourceID
            || previous.title != mediaInfo.title
            || previous.artist != mediaInfo.artist
            || previous.album != mediaInfo.album
            || previous.isPlaying != mediaInfo.isPlaying
            || abs(previous.duration - mediaInfo.duration) > 0.5
            || previous.artworkData?.count != mediaInfo.artworkData?.count

        currentMedia = mediaInfo
        allSources = mediaInfo.isEmpty ? [] : [mediaInfo]

        // Always write on a real change; otherwise throttle to one write per 20 s so
        // the widget's progress bar stays accurate without being reloaded every poll.
        let now = Date()
        guard significantChange || now.timeIntervalSince(lastSharedWrite) > 20 else { return }
        lastSharedWrite = now

        sharedDefaults.save(mediaInfo: mediaInfo)
        sharedDefaults.requestWidgetReload()
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
