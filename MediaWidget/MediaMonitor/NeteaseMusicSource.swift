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
    private var lastReadAttempt = Date.distantPast
    private var bookmark: Data?
    private var selectedFolder: URL?
    private(set) var databaseStatus: NeteaseDatabaseStatus = .notConnected
    private var databaseModification: Date?
    private var cachedTrack: NeteaseTrack?
    private var confirmedTrack: NeteaseTrack?
    private var trackBeforeChange: NeteaseTrack.Identity?
    private var waitingForTrackAfter: Date?

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
        updateConfirmedTrack(state: state, now: .now)
        let track = confirmedTrack
        var capabilities: MediaCapabilities = [.canPlay, .canPause]
        if item(in: items, named: ["下一个", "下一首", "Next"]) != nil { capabilities.insert(.canNextTrack) }
        if item(in: items, named: ["上一个", "上一首", "Previous"]) != nil { capabilities.insert(.canPreviousTrack) }
        return MediaInfo(
            sourceID: bundleID, bundleID: bundleID, sourceName: "网易云音乐", itemID: track?.identity.id,
            title: track?.title ?? "曲目信息不可用", artist: track?.artist, album: track?.album,
            duration: track?.duration, playbackState: state, capabilities: capabilities
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
        if command == .next || command == .previous { refreshTrack() }
        let requestedAt = Date.now
        guard let item = item(in: items, named: names), AccessibilityMedia.press(item) else { return false }
        if command == .next || command == .previous {
            trackBeforeChange = cachedTrack?.identity ?? confirmedTrack?.identity ?? trackBeforeChange
            confirmedTrack = nil
            // SQLite stores milliseconds. Allow for truncation of the command timestamp.
            waitingForTrackAfter = requestedAt.addingTimeInterval(-0.001)
            lastReadAttempt = .distantPast
        }
        return true
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
        trackBeforeChange = nil
        waitingForTrackAfter = nil
    }

    private func updateConfirmedTrack(state: PlaybackState, now: Date) {
        guard let track = cachedTrack else { return }
        if confirmedTrack?.identity == track.identity { return }
        let age = now.timeIntervalSince(track.identity.startedAt)
        guard (0..<30).contains(age) else { return }
        if let waitingForTrackAfter {
            guard track.identity != trackBeforeChange, track.identity.startedAt >= waitingForTrackAfter else { return }
        } else {
            guard state == .playing else { return }
        }
        confirmedTrack = track
        trackBeforeChange = nil
        waitingForTrackAfter = nil
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
            if confirmedTrack?.identity != track?.identity { confirmedTrack = nil }
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
