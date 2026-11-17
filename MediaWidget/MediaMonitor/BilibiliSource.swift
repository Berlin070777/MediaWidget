import AppKit
import ApplicationServices
import CoreGraphics

final class BilibiliSource {
    private typealias AX = AccessibilityMedia
    private let bundleID = Constants.KnownApp.bilibili

    private struct Player {
        let window: AXUIElement
        let container: AXUIElement
        let toggle: AXUIElement
        let timeLabel: AXUIElement?
        let author: AXUIElement?
        let webArea: AXUIElement?
    }

    private var player: Player?
    private(set) var artworkURL: URL?
    private var process: pid_t?
    private var nextDiscovery = Date.distantPast
    private var previousTiming: (title: String?, position: Double, sampledAt: Date)?
    private var playbackObservation = PlaybackState.unknown
    private var changingPlayback = false

    func snapshot(pid: pid_t?) -> MediaInfo? {
        artworkURL = nil
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
        let videoID = player.webArea.flatMap(videoID(for:))
        artworkURL = videoID.flatMap(ArtworkCache.bilibiliReference(videoID:))
        let timing = playbackTiming(player)
        let position = timing?.position
        let duration = timing?.duration
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
                         itemID: videoID ?? title, title: title ?? "视频标题不可用",
                         artist: player.author.flatMap { AX.title($0).nonBlank ?? AX.value($0, "AXValue") },
                         duration: duration,
                         currentPosition: position, playbackState: observed,
                         capabilities: capabilities)
    }

    func perform(_ command: MediaCommand, itemID: String?, pid: pid_t,
                 isolation: isolated (any Actor)? = #isolation) async -> Bool {
        if command == .activate {
            guard process == pid, let player, matches(player, itemID: itemID) else { return false }
            return AXUIElementPerformAction(player.window, kAXRaiseAction as CFString) == .success
        }
        guard command == .play || command == .pause else { return false }
        // A second click can arrive while the first command is still being confirmed.
        for _ in 0..<60 where changingPlayback {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return false }
        }
        guard !changingPlayback, process == pid, let player, matches(player, itemID: itemID) else { return false }
        let classState = state(AX.classes(player.container))
        let actual = classState == .unknown ? playbackObservation : classState
        guard actual != .unknown else { return false }
        let expected: PlaybackState = command == .play ? .playing : .paused
        if actual == expected { return true }

        changingPlayback = true
        defer { changingPlayback = false }
        let fullscreen: Bool = AX.value(player.window, "AXFullScreen") ?? false
        let useClick = fullscreen && CGPreflightPostEventAccess()
        let previousApp = useClick ? NSWorkspace.shared.frontmostApplication : nil
        defer {
            if let previousApp, previousApp.processIdentifier != pid,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                previousApp.activate()
            }
        }

        let sent: Bool
        if useClick {
            // Electron can acknowledge AXPress without dispatching it to the fullscreen player.
            guard let itemID else { return false }
            sent = await clickPlaybackButton(player, pid: pid, itemID: itemID)
        } else {
            _ = AXUIElementPerformAction(player.window, kAXRaiseAction as CFString)
            sent = AX.press(player.toggle)
        }
        guard sent, await confirms(expected, player: player, itemID: itemID) else { return false }
        playbackObservation = expected
        if let timing = playbackTiming(player) {
            previousTiming = (AX.title(player.window).nonBlank, timing.position, .now)
        }
        return true
    }

    private func confirms(_ expected: PlaybackState, player: Player, itemID: String?,
                          isolation: isolated (any Actor)? = #isolation) async -> Bool {
        var sample: (position: TimeInterval, since: Date)?
        for _ in 0..<12 {
            guard !Task.isCancelled, matches(player, itemID: itemID) else { return false }
            if state(AX.classes(player.container)) == expected { return true }
            if let position = playbackTiming(player)?.position {
                let now = Date.now
                if let sample {
                    if expected == .playing && position > sample.position { return true }
                    if expected == .paused && position == sample.position && now.timeIntervalSince(sample.since) >= 2.1 {
                        return true
                    }
                }
                if sample?.position != position { sample = (position, now) }
            } else {
                sample = nil
            }
            try? await Task.sleep(for: .milliseconds(350))
        }
        return false
    }

    private func playbackTiming(_ player: Player) -> (position: TimeInterval, duration: TimeInterval)? {
        guard let label = player.timeLabel else { return nil }
        let values = AX.children(label).compactMap { element -> TimeInterval? in
            let text: String? = AX.value(element, "AXValue")
            return AX.seconds(text)
        }
        return values.count == 2 ? (values[0], values[1]) : nil
    }

    private func matches(_ player: Player, itemID: String?) -> Bool {
        (player.webArea.flatMap(videoID(for:)) ?? AX.title(player.window).nonBlank) == itemID
    }

    private func clickPlaybackButton(_ player: Player, pid: pid_t, itemID: String,
                                     isolation: isolated (any Actor)? = #isolation) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isHidden else { return false }
        app.activate()
        _ = AXUIElementPerformAction(player.window, kAXRaiseAction as CFString)

        for _ in 0..<12 {
            guard !Task.isCancelled, process == pid, matches(player, itemID: itemID) else { return false }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
               let point = buttonCenter(player.toggle), hitTest(point, matches: player.toggle, pid: pid) {
                let cursor = CGEvent(source: nil)?.location
                guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                         mouseCursorPosition: point, mouseButton: .left),
                      let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                         mouseCursorPosition: point, mouseButton: .left),
                      let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                       mouseCursorPosition: point, mouseButton: .left) else { return false }
                move.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(100))
                defer {
                    if let cursor, let current = CGEvent(source: nil)?.location, hypot(current.x - point.x, current.y - point.y) < 2 {
                        CGWarpMouseCursorPosition(cursor)
                    }
                }
                guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                      matches(player, itemID: itemID), hitTest(point, matches: player.toggle, pid: pid),
                      let current = CGEvent(source: nil)?.location,
                      hypot(current.x - point.x, current.y - point.y) < 2 else { return false }
                down.setIntegerValueField(.mouseEventClickState, value: 1)
                up.setIntegerValueField(.mouseEventClickState, value: 1)
                down.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(25))
                up.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(120))
                return true
            }
            try? await Task.sleep(for: .milliseconds(65))
        }
        return false
    }

    private func buttonCenter(_ element: AXUIElement) -> CGPoint? {
        guard AX.enabled(element),
              let position: AXValue = AX.value(element, kAXPositionAttribute),
              let size: AXValue = AX.value(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions),
              origin.x.isFinite, origin.y.isFinite, dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGPoint(x: origin.x + dimensions.width / 2, y: origin.y + dimensions.height / 2)
    }

    private func hitTest(_ point: CGPoint, matches button: AXUIElement, pid: pid_t) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return false }
        var owner: pid_t = 0
        guard AXUIElementGetPid(hit, &owner) == .success, owner == pid else { return false }
        var element: AXUIElement? = hit
        for _ in 0..<5 {
            guard let current = element else { break }
            if CFEqual(current, button) { return true }
            element = AX.value(current, kAXParentAttribute)
        }
        return false
    }

    private func state(_ classes: [String]) -> PlaybackState {
        if classes.contains("bpx-state-playing") { return .playing }
        if classes.contains("bpx-state-paused") || classes.contains("bpx-state-ended") { return .paused }
        return .unknown
    }

    private func videoID(for webArea: AXUIElement) -> String? {
        let raw: URL? = AX.value(webArea, "AXURL")
        guard let raw, raw.host == "bilipc.bilibili.com", raw.path == "/player.html" else { return nil }
        return URLComponents(url: raw, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "bvid" }?.value
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
            let webArea = AX.children(window).first { (AX.value($0, "AXRole") as String?) == "AXWebArea" }
            return Player(window: window, container: container, toggle: toggle,
                          timeLabel: label, author: author, webArea: webArea)
        }
        return nil
    }
}
