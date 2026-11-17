import Foundation

struct MediaCapabilities: OptionSet, Codable, Sendable, Hashable {
    let rawValue: UInt

    static let canPlay = Self(rawValue: 1 << 0)
    static let canPause = Self(rawValue: 1 << 1)
    static let canNextTrack = Self(rawValue: 1 << 2)
    static let canPreviousTrack = Self(rawValue: 1 << 3)
    static let canSeek = Self(rawValue: 1 << 4)
    static let canSetVolume = Self(rawValue: 1 << 5)

    var canTogglePlayPause: Bool { contains(.canPlay) || contains(.canPause) }
    var canSkipNext: Bool { contains(.canNextTrack) }
    var canSkipPrevious: Bool { contains(.canPreviousTrack) }
}

enum PlaybackState: String, Codable, Sendable {
    case playing, paused, unknown
}

enum MediaCommand: String, Codable, Sendable {
    case play, pause, next, previous, seek, volume, activate, selectSource, openPanel

    var capability: MediaCapabilities {
        switch self {
        case .play: .canPlay
        case .pause: .canPause
        case .next: .canNextTrack
        case .previous: .canPreviousTrack
        case .seek, .openPanel: .canSeek
        case .volume: .canSetVolume
        case .activate, .selectSource: []
        }
    }
}

struct MediaInfo: Codable, Sendable, Hashable, Identifiable {
    var id: String { sourceID }
    var sourceID: String
    var bundleID: String
    var sourceName: String
    var itemID: String? = nil
    var title: String
    var artist: String? = nil
    var album: String? = nil
    var artworkData: Data? = nil
    var duration: TimeInterval? = nil
    var currentPosition: TimeInterval? = nil
    var playbackState: PlaybackState
    var playbackRate: Double = 1
    var volume: Float? = nil
    var capabilities: MediaCapabilities = []
    var lastUpdated = Date.now

    var isPlaying: Bool { playbackState == .playing }
    var isEmpty: Bool { sourceID.isEmpty }
    var playPauseCommand: MediaCommand { isPlaying ? .pause : .play }
    var canPlayPause: Bool { capabilities.contains(playPauseCommand.capability) }
    var stateLabel: String {
        switch playbackState {
        case .playing: "播放中"
        case .paused: "已暂停"
        case .unknown: "播放状态不可用"
        }
    }

    var sourceSymbol: String {
        switch bundleID {
        case Constants.KnownApp.neteaseMusic: "music.note"
        case Constants.KnownApp.bilibili: "play.tv.fill"
        case Constants.KnownApp.safari: "safari.fill"
        case Constants.KnownApp.chrome: "globe.americas.fill"
        case Constants.KnownApp.appleMusic: "music.mic"
        case Constants.KnownApp.spotify: "dot.radiowaves.left.and.right"
        default: "app.fill"
        }
    }

    func position(at date: Date = .now) -> TimeInterval? {
        guard let currentPosition, currentPosition.isFinite else { return nil }
        let elapsed = isPlaying ? max(0, date.timeIntervalSince(lastUpdated)) * playbackRate : 0
        return min(max(0, currentPosition + elapsed), duration ?? .infinity)
    }

    static let empty = Self(
        sourceID: "", bundleID: "", sourceName: "", title: "未检测到媒体",
        playbackState: .unknown, lastUpdated: .distantPast
    )

    static func formatTime(_ time: TimeInterval?) -> String {
        guard let time, time.isFinite, time >= 0, time < Double(Int32.max) else { return "不可用" }
        let seconds = Int(time)
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
