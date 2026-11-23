import Foundation

struct AlbumWallCatalog: Sendable {
    var albumID: String?
    var tracks: [Track] = []

    struct Track: Identifiable, Sendable {
        let id: String
        let title: String
        let artist: String?
        let duration: TimeInterval?
    }

    mutating func include(_ track: Track) {
        guard !tracks.contains(where: { $0.id == track.id }) else { return }
        tracks.append(track)
    }
}
