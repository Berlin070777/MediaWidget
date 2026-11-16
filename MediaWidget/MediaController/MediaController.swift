import AppKit

actor MediaController {
    private let netease = NeteaseMusicSource()
    private let bilibili = BilibiliSource()

    struct Reading: Sendable {
        let sources: [MediaInfo]
        let artworkURLs: [String: URL]
        let accessibility: Bool
        let neteaseDatabaseStatus: NeteaseDatabaseStatus
        let systemAudio: SystemAudio.Snapshot
    }

    func read(processes: [String: pid_t], readArtwork: Bool) -> Reading {
        let music = netease.snapshot(pid: processes[Constants.KnownApp.neteaseMusic])
        let video = bilibili.snapshot(pid: processes[Constants.KnownApp.bilibili])
        let desktop = [music.map { ($0, netease.artworkURL) }, video.map { ($0, bilibili.artworkURL) }].compactMap { $0 }
        let web = [BrowserKind.chrome, .safari].flatMap { browser in
            processes[browser.bundleID] == nil ? [] : BrowserBridge.snapshots(browser)
        }
        var artworkURLs: [String: URL] = [:]
        let sources = (desktop + web).map { media, url in
            var media = media
            if readArtwork, let url {
                artworkURLs[media.sourceID] = url
                media.artworkData = ArtworkCache.cached(url)
            } else {
                media.artworkData = nil
            }
            return media
        }
        return Reading(sources: sources, artworkURLs: artworkURLs,
                       accessibility: AccessibilityMedia.isTrusted, neteaseDatabaseStatus: netease.databaseStatus,
                       systemAudio: SystemAudio.snapshot())
    }

    func retryNeteaseDatabaseAccess() { netease.retryDatabaseAccess() }

    func perform(_ action: MediaCommand, media: MediaInfo, pid: pid_t?, value: Double?) -> Bool {
        if BrowserKind.kind(for: media.sourceID) != nil {
            return BrowserBridge.send(action, to: media, value: value)
        }
        if media.bundleID == Constants.KnownApp.bilibili {
            return bilibili.perform(action, itemID: media.itemID)
        }
        guard media.bundleID == Constants.KnownApp.neteaseMusic, let pid else { return false }
        return netease.perform(action, pid: pid)
    }
}
