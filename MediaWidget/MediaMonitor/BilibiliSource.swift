import AppKit
import ApplicationServices

final class BilibiliSource {
    private typealias AX = AccessibilityMedia
    private let bundleID = Constants.KnownApp.bilibili

    private struct Player {
        let window: AXUIElement
        let container: AXUIElement
        let toggle: AXUIElement
        let timeLabel: AXUIElement?
        let author: AXUIElement?
    }

    private var player: Player?
    private var process: pid_t?
    private var nextDiscovery = Date.distantPast
    private var previousTiming: (title: String?, position: Double, sampledAt: Date)?
    private var playbackObservation = PlaybackState.unknown

    func snapshot(pid: pid_t?) -> MediaInfo? {
        guard let pid, AX.isTrusted else {
            player = nil
            process = nil
            return nil
        }
        if process != pid {
            process = pid
            player = nil
            previousTiming = nil
            playbackObservation = .unknown
            nextDiscovery = .distantPast
        }
        if let player, !AX.classes(player.container).contains("bpx-player-container") ||
            !AX.classes(player.toggle).contains("bpx-player-ctrl-play") {
            self.player = nil
            previousTiming = nil
            playbackObservation = .unknown
            nextDiscovery = .distantPast
        }
        if player == nil && Date.now >= nextDiscovery {
            nextDiscovery = Date.now.addingTimeInterval(20)
            player = discover(pid)
        }
        guard let player else { return nil }
        let classes = AX.classes(player.container)
        let title = AX.title(player.window).nonBlank
        let values = player.timeLabel.map(AX.children)?.compactMap { element -> TimeInterval? in
            let text: String? = AX.value(element, "AXValue")
            return AX.seconds(text)
        } ?? []
        let position = values.count == 2 ? values[0] : nil
        let duration = values.count == 2 ? values[1] : nil
        let now = Date.now
        if let position {
            if let previousTiming, previousTiming.title == title {
                let elapsed = now.timeIntervalSince(previousTiming.sampledAt)
                let movement = position - previousTiming.position
                if elapsed >= 1.1 {
                    playbackObservation = movement > 0 && movement <= elapsed * 4 ? .playing : movement == 0 ? .paused : .unknown
                    self.previousTiming = (title, position, now)
                }
            } else {
                playbackObservation = .unknown
                previousTiming = (title, position, now)
            }
        }
        let classState = state(classes)
        let observed = classState == .unknown && position != nil ? playbackObservation : classState
        let capabilities: MediaCapabilities = AX.enabled(player.toggle) && observed != .unknown ? [.canPlay, .canPause] : []
        return MediaInfo(sourceID: bundleID, bundleID: bundleID, sourceName: "哔哩哔哩",
                         itemID: title, title: title ?? "视频标题不可用",
                         artist: player.author.flatMap { AX.title($0).nonBlank ?? AX.value($0, "AXValue") },
                         duration: duration,
                         currentPosition: position, playbackState: observed,
                         capabilities: capabilities)
    }

    func perform(_ command: MediaCommand, itemID: String?) -> Bool {
        guard let player, AX.title(player.window).nonBlank == itemID else { return false }
        if command == .activate {
            return AXUIElementPerformAction(player.window, kAXRaiseAction as CFString) == .success
        }
        guard command == .play || command == .pause else { return false }
        let classState = state(AX.classes(player.container))
        let actual = classState == .unknown ? playbackObservation : classState
        guard actual != .unknown else { return false }
        if (actual == .playing) == (command == .play) { return true }
        // Some Electron versions dispatch the AX press only after the video
        // window has been raised. Never substitute a system-wide media key.
        _ = AXUIElementPerformAction(player.window, kAXRaiseAction as CFString)
        let sent = AX.press(player.toggle)
        if sent {
            previousTiming = nil
            playbackObservation = .unknown
        }
        return sent
    }

    private func state(_ classes: [String]) -> PlaybackState {
        if classes.contains("bpx-state-playing") { return .playing }
        if classes.contains("bpx-state-paused") || classes.contains("bpx-state-ended") { return .paused }
        return .unknown
    }

    private func discover(_ pid: pid_t) -> Player? {
        let app = AX.application(pid)
        let windows: [AXUIElement] = AX.value(app, "AXWindows") ?? []
        for window in windows.prefix(4) {
            guard let container = AX.find(in: window, limit: 180, where: {
                AX.classes($0).contains("bpx-player-container")
            }), let toggle = AX.find(in: container, limit: 100, where: {
                AX.classes($0).contains("bpx-player-ctrl-play")
            }) else { continue }
            let parent: AXUIElement? = AX.value(toggle, "AXParent")
            let time = parent.flatMap { AX.children($0).first { AX.classes($0).contains("bpx-player-ctrl-time") } }
            let label = time.flatMap { AX.children($0).first }
            let author = AX.find(in: window, limit: 280) {
                let classes = AX.classes($0)
                return classes.contains("up-name") || classes.contains("upinfo-name")
            }
            return Player(window: window, container: container, toggle: toggle, timeLabel: label, author: author)
        }
        return nil
    }
}
