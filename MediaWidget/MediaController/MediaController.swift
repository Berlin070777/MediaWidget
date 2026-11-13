import AppKit

actor MediaController {
    private let netease = NeteaseMusicSource()
    private let bilibili = BilibiliSource()

    struct Reading: Sendable {
        let sources: [MediaInfo]
        let artworkURLs: [String: URL]
        let accessibility: Bool
        let systemAudio: SystemAudio.Snapshot
    }

    func read(processes: [String: pid_t], readArtwork: Bool) -> Reading {
        let desktop = [
            netease.snapshot(pid: processes[Constants.KnownApp.neteaseMusic]),
            bilibili.snapshot(pid: processes[Constants.KnownApp.bilibili])
        ].compactMap { $0 }.map { ($0, $0.bundleID == Constants.KnownApp.neteaseMusic ? netease.artworkURL : nil) }
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
                       accessibility: AccessibilityMedia.isTrusted, systemAudio: SystemAudio.snapshot())
    }

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
