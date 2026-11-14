import AppKit
import SQLite3

final class NeteaseMusicSource {
    static let storageDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path:
        "Library/Containers/\(Constants.KnownApp.neteaseMusic)/Data/Documents/storage", directoryHint: .isDirectory)
    static let folderBookmarkKey = "neteaseStorageBookmark"

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
    }

    private let bundleID = Constants.KnownApp.neteaseMusic
    private var process: pid_t?
    private var lastReadAttempt = Date.distantPast
    private var bookmark: Data?
    private var selectedFolder: URL?
    private(set) var databaseReadable: Bool?
    private var databaseModification: Date?
    private var cachedTrack: Track?
    private var confirmedTrack: Track?
    private var waitingForTrackAfter: Date?

    private struct Track {
        let id: String
        let startedAt: Date
        let title: String?
        let artist: String?
        let album: String?
        let duration: TimeInterval?
        let artworkURL: URL?
    }

    func snapshot(pid: pid_t?) -> MediaInfo? {
        guard let pid, AccessibilityMedia.isTrusted else {
            process = nil
            databaseReadable = nil
            confirmedTrack = nil
            return nil
        }
        if pid != process {
            process = pid
            databaseModification = nil
            lastReadAttempt = .distantPast
            confirmedTrack = nil
            waitingForTrackAfter = nil
        }
        guard let items = menu(pid), let state = state(items) else { return nil }
        refreshTrack()
        // The history row can lag behind the menu. Accept only a recent row or one
        // already observed while this instance of the player was active.
        if let track = cachedTrack,
           Date.now.timeIntervalSince(track.startedAt) >= 0,
           (waitingForTrackAfter.map { track.startedAt >= $0 } ??
            (confirmedTrack?.id == track.id ||
             (state == .playing && Date.now.timeIntervalSince(track.startedAt) < 30))) {
            confirmedTrack = track
            waitingForTrackAfter = nil
        }
        let track = confirmedTrack
        var capabilities: MediaCapabilities = [.canPlay, .canPause]
        if item(in: items, named: ["下一个", "下一首", "Next"]) != nil { capabilities.insert(.canNextTrack) }
        if item(in: items, named: ["上一个", "上一首", "Previous"]) != nil { capabilities.insert(.canPreviousTrack) }
        return MediaInfo(
            sourceID: bundleID, bundleID: bundleID, sourceName: "网易云音乐", itemID: track?.id,
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
        guard let item = item(in: items, named: names), AccessibilityMedia.press(item) else { return false }
        if command == .next || command == .previous {
            confirmedTrack = nil
            waitingForTrackAfter = Date.now.addingTimeInterval(-0.5)
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

    private func refreshTrack() {
        let storedBookmark = UserDefaults.standard.data(forKey: Self.folderBookmarkKey)
        if storedBookmark != bookmark {
            bookmark = storedBookmark
            selectedFolder = nil
            databaseReadable = nil
            cachedTrack = nil
            confirmedTrack = nil
            databaseModification = nil
            lastReadAttempt = .distantPast
            if let storedBookmark {
                var stale = false
                selectedFolder = (try? URL(resolvingBookmarkData: storedBookmark, options: .withSecurityScope,
                                           relativeTo: nil, bookmarkDataIsStale: &stale))
                    ?? (try? URL(resolvingBookmarkData: storedBookmark, options: .withoutUI,
                                 relativeTo: nil, bookmarkDataIsStale: &stale))
            }
        }
        let directory = selectedFolder ?? Self.storageDirectory
        let accessing = selectedFolder?.startAccessingSecurityScopedResource() == true
        defer { if accessing { selectedFolder?.stopAccessingSecurityScopedResource() } }
        let url = directory.appending(path: "sqlite_storage.sqlite3")
        let wal = URL(fileURLWithPath: url.path + "-wal")
        let modified = [url, wal].compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()
        guard modified != nil || databaseReadable != false else { return }
        guard databaseModification == nil || modified != databaseModification,
              Date.now.timeIntervalSince(lastReadAttempt) >= 2 else { return }
        lastReadAttempt = .now

        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        let opened = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        databaseReadable = opened
        guard opened else {
            cachedTrack = nil
            confirmedTrack = nil
            return
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT id, playtime, jsonStr FROM historyTracks ORDER BY playtime DESC LIMIT 1"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let id = sqlite3_column_text(statement, 0),
              let json = sqlite3_column_text(statement, 2),
              let object = (try? JSONSerialization.jsonObject(with: Data(String(cString: json).utf8))) as? [String: Any]
        else { return }
        databaseModification = modified
        let duration = (object["duration"] as? NSNumber)?.doubleValue ?? 0
        let album = object["album"] as? [String: Any]
        let artwork = (album?["picUrl"] as? String).flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) }
        cachedTrack = Track(
            id: String(cString: id),
            startedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 1)) / 1000),
            title: (object["name"] as? String)?.nonBlank,
            artist: (object["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: " / ").nonBlank,
            album: (album?["name"] as? String)?.nonBlank,
            duration: duration > 0 && duration.isFinite ? duration / 1000 : nil,
            artworkURL: artwork
        )
        if cachedTrack?.id != confirmedTrack?.id { confirmedTrack = nil }
    }
}
