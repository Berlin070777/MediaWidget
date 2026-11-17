import AppKit

final class NeteaseMusicSource {
    static let storageDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path:
        "Library/Containers/\(Constants.KnownApp.neteaseMusic)/Data/Documents/storage", directoryHint: .isDirectory)
    private static let folderBookmarkKey = "neteaseStorageBookmark"
    private static let accessRequestedKey = "neteaseMetadataAccessRequested"

    static func requestDatabaseAccess() {
        UserDefaults.standard.set(true, forKey: accessRequestedKey)
    }

    static func disconnectDatabase() {
        UserDefaults.standard.removeObject(forKey: folderBookmarkKey)
        UserDefaults.standard.removeObject(forKey: accessRequestedKey)
    }

    static func storeFolderAccess(_ directory: URL) throws {
        guard directory.standardizedFileURL.path == storageDirectory.standardizedFileURL.path else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        // AppKit has already granted access to the selected folder. A bookmark
        // lets the app restore that narrow grant after it exits.
        let bookmark: Data
        do {
            bookmark = try directory.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        } catch {
            bookmark = try directory.bookmarkData()
        }
        UserDefaults.standard.set(bookmark, forKey: folderBookmarkKey)
        requestDatabaseAccess()
    }

    private let bundleID = Constants.KnownApp.neteaseMusic
    private var process: pid_t?
    private var playbackStateFile = NeteasePlaybackState()
    private var progress = NeteaseProgress()
    private var lastLookup: (id: String, date: Date)?
    private var lastReadAttempt = Date.distantPast
    private var bookmark: Data?
    private var selectedFolder: URL?
    private(set) var databaseStatus: NeteaseDatabaseStatus = .notConnected
    private var databaseModification: Date?
    private var cachedTrack: NeteaseTrack?
    private var confirmedTrack: NeteaseTrack?
    private struct PendingChange {
        let previousID: String?
        let requestedAt: Date
    }

    private var pendingChange: PendingChange?

    func retryDatabaseAccess() {
        databaseStatus = .checking
        lastReadAttempt = .distantPast
        databaseModification = nil
    }

    func snapshot(pid: pid_t?) -> MediaInfo? {
        guard let pid, AccessibilityMedia.isTrusted else {
            process = nil
            let configured = UserDefaults.standard.bool(forKey: Self.accessRequestedKey)
                || UserDefaults.standard.data(forKey: Self.folderBookmarkKey) != nil
            databaseStatus = configured ? .waitingForPlayer : .notConnected
            clearTrack()
            return nil
        }
        if pid != process {
            process = pid
            databaseModification = nil
            lastReadAttempt = .distantPast
            if databaseStatus != .permissionRequired { databaseStatus = .checking }
            clearTrack()
        }
        refreshTrack()
        guard let items = menu(pid), let state = state(items) else { return nil }
        let now = Date.now
        let saved = databaseStatus == .readable ? withStorageAccess { playbackStateFile.read(in: $0) } : nil
        updateConfirmedTrack(state: state, savedTrackID: saved?.trackID, now: now)
        let track = confirmedTrack
        let position = progress.position(for: track?.identity.id, duration: track?.duration, sample: saved,
                                         isPlaying: state == .playing, at: now)
        var capabilities: MediaCapabilities = [.canPlay, .canPause]
        if item(in: items, named: ["下一个", "下一首", "Next"]) != nil { capabilities.insert(.canNextTrack) }
        if item(in: items, named: ["上一个", "上一首", "Previous"]) != nil { capabilities.insert(.canPreviousTrack) }
        if let track, let duration = track.duration, duration > 0,
           saved?.trackID == track.identity.id, position != nil, NeteaseSeekControl.canSeek(pid: pid) {
            capabilities.insert(.canSeek)
        }
        return MediaInfo(
            sourceID: bundleID, bundleID: bundleID, sourceName: "网易云音乐", itemID: track?.identity.id,
            title: track?.title ?? "曲目信息不可用", artist: track?.artist, album: track?.album,
            duration: track?.duration, currentPosition: position, playbackState: state,
            capabilities: capabilities, lastUpdated: now
        )
    }

    func perform(_ command: MediaCommand, pid: pid_t) -> Bool {
        guard AccessibilityMedia.isTrusted, let items = menu(pid), let state = state(items) else { return false }
        let names: [String]
        switch command {
        case .play:
            if state == .playing { return true }
            names = ["播放", "Play"]
        case .pause:
            if state == .paused { return true }
            names = ["暂停", "Pause"]
        case .next: names = ["下一个", "下一首", "Next"]
        case .previous: names = ["上一个", "上一首", "Previous"]
        default: return false
        }
        let isTrackChange = command == .next || command == .previous
        let previousID: String?
        if isTrackChange, databaseStatus == .readable {
            previousID = withStorageAccess { playbackStateFile.read(in: $0) }?.trackID ?? confirmedTrack?.identity.id
        } else {
            previousID = nil
        }
        let requestedAt = Date.now
        guard let item = item(in: items, named: names), AccessibilityMedia.press(item) else { return false }
        if isTrackChange {
            pendingChange = PendingChange(previousID: previousID, requestedAt: requestedAt)
            confirmedTrack = nil
            progress = NeteaseProgress()
            lastReadAttempt = .distantPast
            lastLookup = nil
        }
        return true
    }

    func savedPosition(trackID: String, pid: pid_t) -> TimeInterval? {
        guard process == pid, confirmedTrack?.identity.id == trackID, databaseStatus == .readable,
              let sample = withStorageAccess({ playbackStateFile.read(in: $0) }), sample.trackID == trackID else { return nil }
        return sample.position
    }

    var artworkURL: URL? { confirmedTrack?.artworkURL }

    private func menu(_ pid: pid_t) -> [AXUIElement]? {
        let ax = AccessibilityMedia.application(pid)
        guard let bar: AXUIElement = AccessibilityMedia.value(ax, "AXMenuBar"),
              let control = AccessibilityMedia.children(bar).first(where: {
                  ["控制", "Control", "Controls"].contains(AccessibilityMedia.title($0))
              }),
              let menu = AccessibilityMedia.children(control).first else { return nil }
        return AccessibilityMedia.children(menu)
    }

    private func state(_ items: [AXUIElement]) -> PlaybackState? {
        if item(in: items, named: ["暂停", "Pause"]) != nil { return .playing }
        if item(in: items, named: ["播放", "Play"]) != nil { return .paused }
        return nil
    }

    private func item(in items: [AXUIElement], named names: [String]) -> AXUIElement? {
        items.first { names.contains(AccessibilityMedia.title($0)) && AccessibilityMedia.enabled($0) }
    }

    private func clearTrack() {
        cachedTrack = nil
        confirmedTrack = nil
        playbackStateFile = NeteasePlaybackState()
        progress = NeteaseProgress()
        lastLookup = nil
        pendingChange = nil
    }

    private func withStorageAccess<T>(_ read: (URL) -> T) -> T {
        let directory = selectedFolder ?? Self.storageDirectory
        let accessing = selectedFolder?.startAccessingSecurityScopedResource() == true
        defer { if accessing { selectedFolder?.stopAccessingSecurityScopedResource() } }
        return read(directory)
    }

    private func updateConfirmedTrack(state: PlaybackState, savedTrackID: String?, now: Date) {
        if let pendingChange {
            let savedTrackChanged = savedTrackID.map { $0 != pendingChange.previousID } ?? false
            if !savedTrackChanged && now.timeIntervalSince(pendingChange.requestedAt) < 8 {
                // A skip can be ignored or replay the same track. Wait briefly for
                // the ID to change before accepting that track's artwork again.
                return
            }
            self.pendingChange = nil
        }

        if let id = savedTrackID {
            if confirmedTrack?.identity.id != id { confirmedTrack = nil }
            if let current = playbackStateFile.currentTrack,
               current.artworkURL != nil || confirmedTrack?.artworkURL == nil {
                confirmedTrack = current
            }
            if let history = cachedTrack, history.identity.id == id,
               confirmedTrack == nil || (confirmedTrack?.artworkURL == nil && history.artworkURL != nil) {
                confirmedTrack = history
            }
            guard confirmedTrack?.artworkURL == nil else { return }
            if let lastLookup, lastLookup.id == id, now.timeIntervalSince(lastLookup.date) < 15 { return }
            lastLookup = (id, now)
            if case .track(let track?) = withStorageAccess({ NeteaseTrackDatabase.read(in: $0, trackID: id) }),
               confirmedTrack == nil || track.artworkURL != nil {
                confirmedTrack = track
            }
            return
        }

        if let history = cachedTrack, let startedAt = history.identity.startedAt, state == .playing,
           (0..<30).contains(now.timeIntervalSince(startedAt)) {
            confirmedTrack = history
        }
    }

    private func refreshTrack() {
        let storedBookmark = UserDefaults.standard.data(forKey: Self.folderBookmarkKey)
        guard storedBookmark != nil || UserDefaults.standard.bool(forKey: Self.accessRequestedKey) else {
            if databaseStatus != .notConnected {
                bookmark = nil
                selectedFolder = nil
                clearTrack()
                databaseStatus = .notConnected
            }
            return
        }
        if storedBookmark != bookmark {
            bookmark = storedBookmark
            selectedFolder = nil
            clearTrack()
            retryDatabaseAccess()
            if let storedBookmark {
                var stale = false
                selectedFolder = (try? URL(resolvingBookmarkData: storedBookmark, options: [.withSecurityScope, .withoutUI],
                                           relativeTo: nil, bookmarkDataIsStale: &stale))
                    ?? (try? URL(resolvingBookmarkData: storedBookmark, options: .withoutUI,
                                 relativeTo: nil, bookmarkDataIsStale: &stale))
            }
        }
        // macOS remembers a denied request. Let the person retry once the
        // setting changes, without polling the protected file in the meantime.
        guard databaseStatus != .permissionRequired else { return }
        let now = Date.now
        let interval: TimeInterval = databaseStatus == .temporarilyUnavailable ? 5 : 2
        guard now.timeIntervalSince(lastReadAttempt) >= interval else { return }
        let directory = selectedFolder ?? Self.storageDirectory
        let accessing = selectedFolder?.startAccessingSecurityScopedResource() == true
        defer { if accessing { selectedFolder?.stopAccessingSecurityScopedResource() } }
        let url = directory.appending(path: NeteaseTrackDatabase.fileName)
        let wal = directory.appending(path: NeteaseTrackDatabase.fileName + "-wal")
        let modified = [url, wal].compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()
        // Occasionally recheck even if filesystem timestamps appear unchanged.
        if databaseStatus == .readable, let modified, modified == databaseModification,
           now.timeIntervalSince(lastReadAttempt) < 15 { return }
        lastReadAttempt = now

        switch NeteaseTrackDatabase.read(in: directory) {
        case .track(let track):
            databaseStatus = .readable
            databaseModification = modified
            cachedTrack = track
        case .failed(let status):
            databaseStatus = status
            databaseModification = nil
            if status != .temporarilyUnavailable {
                cachedTrack = nil
                confirmedTrack = nil
            }
        }
    }
}
