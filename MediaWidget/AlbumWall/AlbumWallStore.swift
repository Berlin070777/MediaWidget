import CryptoKit
import Foundation
import Observation

struct WallAlbum: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String?
    let sourceName: String
    var lastPlayedAt: Date?
    var isFavorite = false
    var artworkVersion: String?
    var backArtworkVersion: String?
    var backReleaseID: UUID?
    var backSourceURL: URL?
    var neteaseAlbumID: String?

    var isNetease: Bool { sourceName == "网易云音乐" }

    init?(media: MediaInfo) {
        let musicSources = [Constants.KnownApp.neteaseMusic, Constants.KnownApp.appleMusic, Constants.KnownApp.spotify]
        guard musicSources.contains(media.bundleID), let album = media.album?.nonBlank else { return nil }
        let identity: [String]
        if let albumID = media.albumID?.nonBlank {
            identity = [media.bundleID, "album", albumID]
        } else if let artist = media.artist?.nonBlank {
            identity = [media.bundleID, "names", album.lowercased(), artist.lowercased()]
        } else if let itemID = media.itemID?.nonBlank {
            identity = [media.bundleID, "track", itemID]
        } else {
            return nil
        }
        id = Self.digest(Data(identity.joined(separator: "\u{0}").utf8))
        title = album
        artist = media.artist?.nonBlank
        sourceName = media.sourceName
        neteaseAlbumID = media.bundleID == Constants.KnownApp.neteaseMusic ? media.albumID : nil
    }

    func matches(_ track: NeteaseTrack) -> Bool {
        guard isNetease else { return false }
        if let neteaseAlbumID { return neteaseAlbumID == track.albumID }
        var media = MediaInfo(sourceID: Constants.KnownApp.neteaseMusic, bundleID: Constants.KnownApp.neteaseMusic,
                              sourceName: sourceName, itemID: track.identity.id, title: track.title ?? "",
                              artist: track.artist, album: track.album, albumID: track.albumID, playbackState: .unknown)
        if WallAlbum(media: media)?.id == id { return true }
        media.albumID = nil
        return WallAlbum(media: media)?.id == id
    }

    fileprivate static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
@Observable
final class AlbumWallStore {
    static let shared = AlbumWallStore(widgetStore: .shared)
    static let historyPreference = "recordRecentAlbums"
    private static let recentLimit = 40

    private(set) var albums: [WallAlbum] = []
    private(set) var errorMessage: String?
    private let directory: URL
    private let widgetStore: SharedDefaults?
    private var activeAlbumIDs: Set<String> = []
    private var indexReadable = true
    private var widgetShowsArtwork = true
    private var requestedPreview: [PreviewCover]?
    private var previewTask: Task<Void, Never>?

    private var backLookups: [String: BackLookup] = [:]

    private struct BackLookup {
        let status: AlbumBackArtworkStatus
        let retryAfter: Date
    }

    private struct PreviewCover: Equatable {
        let id: String
        let title: String
        let artwork: AlbumArtwork.Request
    }

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "MediaWidget/AlbumWall"),
         widgetStore: SharedDefaults? = nil) {
        self.directory = directory
        self.widgetStore = widgetStore
        do {
            albums = try JSONDecoder().decode([WallAlbum].self, from: Data(contentsOf: index))
        } catch CocoaError.fileReadNoSuchFile {
            // A new library starts empty.
        } catch {
            indexReadable = false
            errorMessage = "无法读取本机唱片墙。"
        }
    }

    var recentAlbums: [WallAlbum] {
        albums.filter { $0.lastPlayedAt != nil }.sorted {
            ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast)
        }
    }

    var favorites: [WallAlbum] {
        albums.filter(\.isFavorite).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func playingAlbum(for media: MediaInfo) -> WallAlbum? {
        guard media.isPlaying, let album = WallAlbum(media: media) else { return nil }
        return albums.first { $0.id == album.id }
    }

    func observe(_ sources: [MediaInfo], recordHistory: Bool, at date: Date = .now, showArtwork: Bool? = nil) {
        let visibilityChanged = showArtwork.map { $0 != widgetShowsArtwork } ?? false
        if let showArtwork { widgetShowsArtwork = showArtwork }
        defer {
            if visibilityChanged || requestedPreview == nil { publishWidgetPreview() }
        }
        guard indexReadable else { return }
        var next = albums
        var playingIDs: Set<String> = []
        for media in sources {
            guard let album = WallAlbum(media: media) else { continue }
            if media.isPlaying { playingIDs.insert(album.id) }
            let newlyPlaying = media.isPlaying && !activeAlbumIDs.contains(album.id)
            let index = next.firstIndex { $0.id == album.id }
            guard index != nil || (recordHistory && newlyPlaying) else { continue }
            var updated = index.map { next[$0] } ?? album
            if updated.neteaseAlbumID == nil { updated.neteaseAlbumID = album.neteaseAlbumID }
            if recordHistory && newlyPlaying { updated.lastPlayedAt = date }
            updateArtwork(media.artworkData, on: &updated)
            if let index { next[index] = updated } else { next.append(updated) }
        }
        if save(next) { activeAlbumIDs = recordHistory ? playingIDs : [] }
    }

    func isFavorite(_ id: String) -> Bool {
        albums.contains { $0.id == id && $0.isFavorite }
    }

    func rememberNeteaseAlbumID(_ albumID: String, for id: String) {
        guard let index = albums.firstIndex(where: { $0.id == id && $0.isNetease && $0.neteaseAlbumID == nil }) else { return }
        var entries = albums
        entries[index].neteaseAlbumID = albumID
        _ = save(entries)
    }

    func toggleFavorite(_ album: WallAlbum, artwork: Data? = nil) {
        guard indexReadable else { return }
        var next = albums
        let index = next.firstIndex { $0.id == album.id }
        var updated = index.map { next[$0] } ?? album
        if index == nil { updated.lastPlayedAt = nil }
        updated.isFavorite.toggle()
        updateArtwork(artwork, on: &updated)
        if let index { next[index] = updated } else { next.append(updated) }
        _ = save(next)
    }

    func clearRecents() {
        let cleared = albums.map { album in
            var updated = album
            updated.lastPlayedAt = nil
            return updated
        }
        _ = save(cleared)
    }

    func removeFromRecents(_ id: String) {
        guard let index = albums.firstIndex(where: { $0.id == id && $0.lastPlayedAt != nil }) else { return }
        var entries = albums
        entries[index].lastPlayedAt = nil
        _ = save(entries)
    }

    func artwork(for album: WallAlbum) -> AlbumArtwork.Request? {
        guard let version = album.artworkVersion else { return nil }
        return .init(url: artworkFile(for: album.id), version: version)
    }

    func backArtwork(for album: WallAlbum) -> AlbumArtwork.Request? {
        guard let version = album.backArtworkVersion else { return nil }
        return .init(url: backArtworkFile(for: album.id, version: version), version: version)
    }

    func backLookupStatus(for album: WallAlbum) -> AlbumBackArtworkStatus {
        backLookups[album.id]?.status ?? .searching
    }

    func startBackLookup(for album: WallAlbum, retry: Bool = false, using resolver: AlbumBackArtworkLookup = .shared) {
        let previous = backLookups[album.id]
        guard indexReadable, let current = albums.first(where: { $0.id == album.id }),
              current.backArtworkVersion == nil, previous?.status != .searching,
              retry || (previous?.retryAfter ?? .distantPast) <= .now else { return }
        backLookups[album.id] = BackLookup(status: .searching, retryAfter: .distantFuture)
        Task { [weak self] in
            do {
                let match = try await resolver.find(title: current.title, artist: current.artist)
                guard let self, albums.contains(where: { $0.id == album.id && $0.backArtworkVersion == nil }) else { return }
                if let match {
                    if !saveBackArtwork(match.artwork, releaseID: match.releaseID, sourceURL: match.sourceURL, for: album.id) {
                        backLookups[album.id] = BackLookup(status: .unavailable, retryAfter: .now.addingTimeInterval(30))
                    }
                } else {
                    backLookups[album.id] = BackLookup(status: .noMatch, retryAfter: .now.addingTimeInterval(24 * 60 * 60))
                }
            } catch {
                guard let self, albums.contains(where: { $0.id == album.id && $0.backArtworkVersion == nil }) else { return }
                let noScan = (error as? AlbumBackArtworkLookup.Failure) == .noScan
                backLookups[album.id] = BackLookup(status: noScan ? .noScan : .unavailable,
                                                  retryAfter: .now.addingTimeInterval(noScan ? 24 * 60 * 60 : 30))
            }
        }
    }

    func saveBackArtwork(_ data: Data, releaseID: UUID?, sourceURL: URL? = nil, for id: String) -> Bool {
        guard indexReadable, let index = albums.firstIndex(where: { $0.id == id }) else { return false }
        let previous = backArtwork(for: albums[index])?.url
        let version = WallAlbum.digest(data)
        let destination = backArtworkFile(for: id, version: version)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            return false
        }

        var entries = albums
        entries[index].backArtworkVersion = version
        entries[index].backReleaseID = releaseID
        entries[index].backSourceURL = sourceURL
        guard save(entries) else {
            if destination != previous { try? FileManager.default.removeItem(at: destination) }
            return false
        }
        if let previous, previous != destination { try? FileManager.default.removeItem(at: previous) }
        backLookups[id] = nil
        return true
    }

    private func backArtworkFile(for id: String, version: String) -> URL {
        directory.appending(path: id + "-back-" + version + ".jpg")
    }

    private func publishWidgetPreview() {
        guard let widgetStore else { return }
        var covers: [PreviewCover] = []
        if widgetShowsArtwork {
            var seen: Set<String> = []
            for album in recentAlbums + favorites {
                guard let artwork = artwork(for: album), seen.insert(album.id).inserted else { continue }
                covers.append(PreviewCover(id: album.id, title: album.title, artwork: artwork))
                if covers.count == 4 { break }
            }
        }
        guard covers != requestedPreview else { return }
        requestedPreview = covers
        previewTask?.cancel()
        previewTask = Task { [weak self, covers] in
            var preview: [WidgetAlbum] = []
            for cover in covers {
                guard !Task.isCancelled else { return }
                if let thumbnail = await AlbumArtwork.shared.widgetThumbnail(cover.artwork) {
                    preview.append(WidgetAlbum(id: cover.id, title: cover.title, thumbnail: thumbnail))
                }
            }
            guard !Task.isCancelled, let self else { return }
            do {
                if widgetStore.albumPreview() != preview { try widgetStore.saveAlbumPreview(preview) }
            } catch {
                requestedPreview = nil
            }
        }
    }

    private var index: URL { directory.appending(path: "albums.json") }

    private func artworkFile(for id: String) -> URL {
        directory.appending(path: id + ".jpg")
    }

    private func updateArtwork(_ data: Data?, on album: inout WallAlbum) {
        guard let data, !data.isEmpty else { return }
        let version = WallAlbum.digest(data)
        guard version != album.artworkVersion else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: artworkFile(for: album.id), options: .atomic)
            album.artworkVersion = version
        } catch {
            errorMessage = "无法保存唱片封面。"
        }
    }

    @discardableResult
    private func save(_ entries: [WallAlbum]) -> Bool {
        guard indexReadable else { return false }
        let recentIDs = Set(entries.compactMap { album in
            album.lastPlayedAt.map { (album.id, $0) }
        }.sorted { $0.1 > $1.1 }.prefix(Self.recentLimit).map(\.0))
        let kept = entries.compactMap { album -> WallAlbum? in
            if recentIDs.contains(album.id) { return album }
            guard album.isFavorite else { return nil }
            var favorite = album
            favorite.lastPlayedAt = nil
            return favorite
        }
        guard kept != albums else { return true }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(kept).write(to: index, options: .atomic)
        } catch {
            errorMessage = "无法保存本机唱片墙。"
            return false
        }
        let keptIDs = Set(kept.map(\.id))
        let removed = albums.filter { !keptIDs.contains($0.id) }
        albums = kept
        for album in removed {
            backLookups[album.id] = nil
            try? FileManager.default.removeItem(at: artworkFile(for: album.id))
            if let back = backArtwork(for: album) { try? FileManager.default.removeItem(at: back.url) }
        }
        publishWidgetPreview()
        return true
    }
}
