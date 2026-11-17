import AppKit

actor MediaController {
    private let netease = NeteaseMusicSource()
    private let bilibili = BilibiliSource()
    private var neteaseSeekRequest: UUID?

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

    func perform(_ action: MediaCommand, media: MediaInfo, pid: pid_t?, value: Double?) async -> Bool {
        if BrowserKind.kind(for: media.sourceID) != nil {
            return BrowserBridge.send(action, to: media, value: value)
        }
        if media.bundleID == Constants.KnownApp.bilibili {
            guard let pid else { return false }
            return await bilibili.perform(action, itemID: media.itemID, pid: pid)
        }
        guard media.bundleID == Constants.KnownApp.neteaseMusic, let pid else { return false }
        if action == .seek, let value, let itemID = media.itemID, let duration = media.duration {
            return await seekNetease(to: value, duration: duration, media: media, itemID: itemID, pid: pid)
        }
        return netease.perform(action, pid: pid)
    }

    private func seekNetease(to position: Double, duration: Double, media: MediaInfo, itemID: String, pid: pid_t) async -> Bool {
        guard position.isFinite, duration.isFinite, duration > 0,
              let before = netease.savedPosition(trackID: itemID, pid: pid) else { return false }
        if let current = media.position(), abs(current - position) < 1 { return true }
        let request = UUID()
        neteaseSeekRequest = request
        defer { if neteaseSeekRequest == request { neteaseSeekRequest = nil } }
        let started = Date.now
        let sent = await NeteaseSeekControl.seek(pid: pid, fraction: position / duration) {
            await self.checkNeteaseSeek(request, trackID: itemID, pid: pid)
        }
        guard sent else { return neteaseSeekRequest != request }
        for _ in 0..<30 {
            if neteaseSeekRequest != request { return true }
            if Task.isCancelled { return false }
            if let current = netease.savedPosition(trackID: itemID, pid: pid), current != before {
                let elapsed = media.isPlaying ? Date.now.timeIntervalSince(started) : 0
                if current >= position - 3, current <= position + elapsed + 3 { return true }
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return false
    }

    private func checkNeteaseSeek(_ request: UUID, trackID: String, pid: pid_t) -> Bool {
        neteaseSeekRequest == request && netease.savedPosition(trackID: trackID, pid: pid) != nil
    }
}
