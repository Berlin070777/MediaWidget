import AppKit

@MainActor
enum NeteaseAlbumPlayback {
    enum Target {
        case album(String)
        case song(String)

        var link: URL? {
            let type: String
            let rawID: String
            switch self {
            case .album(let id): (type, rawID) = ("album", id)
            case .song(let id): (type, rawID) = ("song", id)
            }
            guard rawID.utf8.allSatisfy({ (48...57).contains($0) }), let id = Int64(rawID), id > 0 else { return nil }
            // NetEase's website sends a base64-encoded play request to its client.
            let payload = Data("{\"type\":\"\(type)\",\"id\":\(id),\"cmd\":\"play\"}".utf8)
            return URL(string: "orpheus://" + payload.base64EncodedString())
        }

        func matches(_ media: MediaInfo) -> Bool {
            guard media.bundleID == Constants.KnownApp.neteaseMusic, media.isPlaying else { return false }
            switch self {
            case .album(let id): return media.albumID == id
            case .song(let id): return media.itemID == id
            }
        }
    }

    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Constants.KnownApp.neteaseMusic)
    }

    static func play(_ target: Target, confirm: () async -> Bool) async -> String? {
        guard let link = target.link else { return "找不到网易云的播放编号。" }
        guard let applicationURL else { return "找不到网易云音乐客户端。" }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.open([link], withApplicationAt: applicationURL, configuration: configuration)
        } catch {
            return "无法把播放请求交给网易云音乐。"
        }
        return await confirm() ? nil : "网易云未确认开始播放。请检查客户端窗口、登录状态或曲目权限。"
    }
}
