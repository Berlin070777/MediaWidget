import AppKit
import Combine
import os
import SafariServices

@MainActor
final class MediaMonitor: ObservableObject {
    static let shared = MediaMonitor()

    @Published private(set) var currentMedia = MediaInfo.empty
    @Published private(set) var allSources: [MediaInfo] = []
    @Published private(set) var systemAudio = SystemAudio.Snapshot()
    @Published private(set) var accessibility = false
    @Published private(set) var neteaseDatabaseStatus: NeteaseDatabaseStatus = .notConnected
    @Published private(set) var sharedStorageError = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var preferredSource = ""
    @Published private(set) var isMonitoring = false

    private let controller = MediaController()
    private let store = SharedDefaults.shared
    private var timer: Timer?
    private var showPanel: (() -> Void)?
    private var refreshTask: Task<Void, Never>?
    private var refreshAgain = false
    private var sleeping = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastSnapshot: WidgetSnapshot?
    private var artworkTasks: Set<URL> = []
    private var artworkRetries: [URL: Date] = [:]
    private var scriptedSources: [(MediaInfo, URL?)] = []
    private var scriptPoll = Date.distantPast
    private static let logger = Logger(subsystem: "com.mediawidget.app", category: "Monitor")

    var showArtwork: Bool { UserDefaults.standard.object(forKey: "showArtwork") as? Bool ?? true }

    func startMonitoring(showPanel: @escaping () -> Void) {
        guard !isMonitoring else { return }
        self.showPanel = showPanel
        isMonitoring = true
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let name = note.name
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if name == NSWorkspace.willSleepNotification {
                        sleeping = true
                        timer?.invalidate()
                        refreshTask?.cancel()
                        publish(.empty, force: true)
                    } else if name == NSWorkspace.didWakeNotification {
                        sleeping = false
                        refreshNowPlaying()
                    } else {
                        refreshNowPlaying()
                    }
                }
            })
        }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, Unmanaged.passUnretained(self).toOpaque(), { _, pointer, _, _, _ in
            guard let pointer else { return }
            let monitor = Unmanaged<MediaMonitor>.fromOpaque(pointer).takeUnretainedValue()
            Task { @MainActor in monitor.readWidgetCommands() }
        }, Constants.commandNotification as CFString, nil, .deliverImmediately)
        refreshNowPlaying()
    }

    func stopMonitoring() {
        isMonitoring = false
        showPanel = nil
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                Unmanaged.passUnretained(self).toOpaque())
        publish(.empty, force: true)
    }

    func refreshNowPlaying() {
        guard isMonitoring, !sleeping else { return }
        if refreshTask != nil {
            refreshAgain = true
            return
        }
        let apps = NSWorkspace.shared.runningApplications.reduce(into: [String: pid_t]()) { result, app in
            if let id = app.bundleIdentifier { result[id] = app.processIdentifier }
        }
        let readArtwork = showArtwork
        refreshTask = Task {
            let reading = await controller.read(processes: apps, readArtwork: readArtwork)
            refreshTask = nil
            guard !Task.isCancelled, isMonitoring, !sleeping else {
                if refreshAgain {
                    refreshAgain = false
                    refreshNowPlaying()
                }
                return
            }
            if accessibility != reading.accessibility { accessibility = reading.accessibility }
            if neteaseDatabaseStatus != reading.neteaseDatabaseStatus {
                neteaseDatabaseStatus = reading.neteaseDatabaseStatus
            }
            if reading.systemAudio != systemAudio { systemAudio = reading.systemAudio }
            var sources = reading.sources
            var urls = reading.artworkURLs
            if UserDefaults.standard.bool(forKey: "scriptedPlayers") {
                if Date.now.timeIntervalSince(scriptPoll) >= 8 {
                    scriptedSources = ScriptingPlayerSource.snapshots()
                    scriptPoll = .now
                }
                for (var media, url) in scriptedSources where apps[media.bundleID] != nil {
                    if readArtwork, let url {
                        media.artworkData = ArtworkCache.cached(url)
                        urls[media.sourceID] = url
                    }
                    sources.append(media)
                }
            } else {
                scriptedSources = []
                scriptPoll = .distantPast
            }

            let ordered = sources.sorted(by: sourceOrder)
            if allSources != ordered { allSources = ordered }
            if !preferredSource.isEmpty && !allSources.contains(where: { $0.sourceID == preferredSource }) {
                preferredSource = ""
            }
            updateSelection()
            if readArtwork, showArtwork, UserDefaults.standard.object(forKey: "downloadArtwork") as? Bool ?? true,
               let url = urls[currentMedia.sourceID], currentMedia.artworkData == nil {
                requestArtwork(url)
            }
            readWidgetCommands()
            if refreshAgain {
                refreshAgain = false
                refreshNowPlaying()
            } else {
                scheduleNextPoll()
            }
        }
    }

    func retryNeteaseDatabaseAccess() async {
        await controller.retryNeteaseDatabaseAccess()
        refreshNowPlaying()
    }

    func chooseSource(_ id: String) {
        preferredSource = id
        updateSelection()
        refreshNowPlaying()
    }

    func submit(_ action: MediaCommand, for media: MediaInfo) {
        guard [.play, .pause, .next, .previous, .activate].contains(action) else { return }
        send(action, for: media, value: nil)
    }

    func seek(_ position: Double, for media: MediaInfo) {
        guard currentMedia.sourceID == media.sourceID, currentMedia.itemID == media.itemID,
              let duration = media.duration, duration.isFinite, duration > 0,
              position.isFinite, media.capabilities.contains(.canSeek) else { return }
        send(.seek, for: media, value: min(max(0, position), duration))
    }

    func setMediaVolume(_ volume: Double, for media: MediaInfo) {
        guard volume.isFinite, media.capabilities.contains(.canSetVolume) else { return }
        send(.volume, for: media, value: min(max(0, volume), 1))
    }

    func setSystemVolume(_ volume: Double) {
        if !SystemAudio.setVolume(Float(volume)) { errorMessage = "当前输出设备无法调节音量" }
        systemAudio = SystemAudio.snapshot()
    }

    func toggleSystemMute() {
        if !SystemAudio.toggleMute() { errorMessage = "当前输出设备无法切换静音" }
        systemAudio = SystemAudio.snapshot()
    }

    private func send(_ action: MediaCommand, for media: MediaInfo, value: Double?) {
        errorMessage = nil
        guard let target = allSources.first(where: { $0.sourceID == media.sourceID && $0.itemID == media.itemID }),
              abs(target.lastUpdated.timeIntervalSinceNow) < (BrowserKind.kind(for: target.sourceID)?.snapshotLifetime ?? 30),
              target.capabilities.contains(action.capability) else {
            errorMessage = "媒体来源已变更"
            return
        }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: media.bundleID).first
        if action == .activate {
            guard let app, app.activate() else {
                errorMessage = "无法打开来源应用"
                return
            }
            if media.bundleID != Constants.KnownApp.bilibili && BrowserKind.kind(for: media.sourceID) == nil { return }
        }
        Task {
            let sent: Bool
            if [Constants.KnownApp.appleMusic, Constants.KnownApp.spotify].contains(media.bundleID) {
                sent = ScriptingPlayerSource.perform(action, bundleID: media.bundleID, value: value)
            } else {
                sent = await controller.perform(action, media: target, pid: app?.processIdentifier, value: value)
            }
            if sent && BrowserKind.kind(for: media.sourceID) == .safari,
               let document = media.sourceID.split(separator: ":").last?.suffix(36),
               let id = UUID(uuidString: String(document)) {
                SFSafariApplication.dispatchMessage(withName: "mediawidget-refresh",
                    toExtensionWithIdentifier: "com.mediawidget.app.safari",
                    userInfo: ["documentID": id.uuidString.lowercased()]) { @Sendable error in
                        if let error {
                            Logger(subsystem: "com.mediawidget.app", category: "Monitor")
                                .debug("Safari wake-up: \(error.localizedDescription, privacy: .private)")
                        }
                    }
            }
            if !sent && action != .activate {
                Self.logger.notice("Source did not accept action \(action.rawValue, privacy: .public)")
                errorMessage = action == .seek ? "未确认进度跳转，请检查播放器窗口" : "来源没有接受该操作"
            }
            try? await Task.sleep(for: .milliseconds(450))
            scriptPoll = .distantPast
            refreshNowPlaying()
        }
    }

    private func readWidgetCommands() {
        guard isMonitoring, !sleeping else { return }
        for command in store.takeCommands() {
            if command.action == .openPanel {
                Self.logger.notice("Opening the media panel from the widget")
                showPanel?()
                continue
            }
            if command.action == .selectSource {
                let sourceIDs = allSources.map(\.sourceID)
                let next = WidgetSourceSwitchIntent.nextSource(after: preferredSource, in: sourceIDs)
                if next != preferredSource {
                    chooseSource(next)
                } else {
                    store.requestWidgetReload()
                }
                continue
            }
            guard [.play, .pause, .previous, .next, .activate].contains(command.action),
                  currentMedia.sourceID == command.sourceID, currentMedia.itemID == command.itemID,
                  !currentMedia.isEmpty else {
                Self.logger.notice("Widget command discarded because the source changed")
                store.requestWidgetReload()
                continue
            }
            Self.logger.notice("Routing widget action \(command.action.rawValue, privacy: .public) to \(self.currentMedia.bundleID, privacy: .public)")
            send(command.action, for: currentMedia, value: nil)
        }
    }

    private func updateSelection() {
        let selected = allSources.first { $0.sourceID == preferredSource }
            ?? allSources.first(where: \.isPlaying)
            ?? allSources.first(where: { $0.sourceID == currentMedia.sourceID && $0.canPlayPause })
            ?? allSources.first(where: { !$0.capabilities.isEmpty })
            ?? allSources.first
            ?? .empty
        if currentMedia != selected { currentMedia = selected }
        publish(selected)
    }

    private func sourceOrder(_ lhs: MediaInfo, _ rhs: MediaInfo) -> Bool {
        let priority = [Constants.KnownApp.neteaseMusic, Constants.KnownApp.bilibili,
                        Constants.KnownApp.safari, Constants.KnownApp.chrome,
                        Constants.KnownApp.appleMusic, Constants.KnownApp.spotify]
        let left = priority.firstIndex(of: lhs.bundleID) ?? priority.count
        let right = priority.firstIndex(of: rhs.bundleID) ?? priority.count
        return left == right ? lhs.sourceID < rhs.sourceID : left < right
    }

    private func publish(_ media: MediaInfo, force: Bool = false) {
        let now = Date.now
        let artwork = showArtwork
        let summaries = (media.isEmpty ? [] : allSources).map {
            WidgetSourceSummary(sourceID: $0.sourceID, bundleID: $0.bundleID,
                                name: $0.sourceName, title: $0.title, isPlaying: $0.isPlaying)
        }
        let previous = lastSnapshot?.media ?? .empty
        let previousSources = lastSnapshot?.sources ?? []
        // The widget presents the active item's title and playback state.
        // Changes to other tabs' tracks don't change its source selector.
        let sameSources = previousSources.elementsEqual(summaries) {
            $0.sourceID == $1.sourceID && $0.bundleID == $1.bundleID && $0.name == $1.name
        }
        let positionTolerance: TimeInterval = media.isPlaying ? 4 : 0.75
        let changed = lastSnapshot == nil || lastSnapshot?.showArtwork != artwork ||
            !sameSources || lastSnapshot?.preferredSource != preferredSource ||
            previous.sourceID != media.sourceID || previous.itemID != media.itemID ||
            previous.title != media.title || previous.artist != media.artist || previous.album != media.album ||
            previous.playbackState != media.playbackState || previous.capabilities != media.capabilities ||
            previous.duration != media.duration || previous.volume != media.volume || previous.artworkData != media.artworkData ||
            previous.playbackRate != media.playbackRate || (previous.currentPosition == nil) != (media.currentPosition == nil) ||
            abs((previous.position(at: now) ?? 0) - (media.position(at: now) ?? 0)) > positionTolerance
        let heartbeat = !media.isEmpty && now.timeIntervalSince(lastSnapshot?.writtenAt ?? .distantPast) >= 25
        guard changed || heartbeat || force else { return }
        let snapshot = WidgetSnapshot(media: media, writtenAt: now, showArtwork: artwork,
                                      sources: summaries, preferredSource: preferredSource)
        do {
            try store.save(snapshot)
            lastSnapshot = snapshot
            if sharedStorageError { sharedStorageError = false }
            if changed || force { store.requestWidgetReload() }
        } catch {
            if !sharedStorageError {
                Self.logger.error("Widget snapshot write failed: \(error.localizedDescription, privacy: .private)")
            }
            sharedStorageError = true
        }
    }

    private func scheduleNextPoll() {
        timer?.invalidate()
        let slow = UserDefaults.standard.bool(forKey: "reducePolling")
        let interval: TimeInterval = slow ? 8 : 3
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshNowPlaying() }
        }
        timer?.tolerance = 0.5
    }

    private func requestArtwork(_ url: URL) {
        let now = Date.now
        artworkRetries = artworkRetries.filter { $0.value > now }
        guard artworkRetries[url] == nil, artworkTasks.insert(url).inserted else { return }
        Task {
            let downloaded = await ArtworkCache.download(url)
            artworkTasks.remove(url)
            if downloaded {
                refreshNowPlaying()
            } else {
                artworkRetries[url] = .now.addingTimeInterval(30)
            }
        }
    }
}
