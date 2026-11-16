import AppKit

@MainActor
enum ScriptingPlayerSource {
    static func snapshots() -> [(MediaInfo, URL?)] {
        [Constants.KnownApp.appleMusic, Constants.KnownApp.spotify].compactMap { bundleID in
            guard isRunning(bundleID) else { return nil }
            let spotify = bundleID == Constants.KnownApp.spotify
            let fields = """
            if player state is stopped then return {}
            set t to current track
            return {(player state as string), (name of t), (artist of t), (album of t), (duration of t as string), (player position as string), (sound volume as string)\(spotify ? ", (artwork url of t)" : "")}
            """
            guard let result = execute(fields, bundleID: bundleID), result.numberOfItems >= 7 else { return nil }
            func field(_ index: Int) -> String? { result.atIndex(index)?.stringValue?.nonBlank }
            func number(_ index: Int) -> Double? {
                field(index).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            }
            let duration = number(5).map { spotify ? $0 / 1000 : $0 }
            let position = number(6)
            var capabilities: MediaCapabilities = [.canPlay, .canPause, .canNextTrack, .canPreviousTrack]
            if duration ?? 0 > 0 && position != nil { capabilities.insert(.canSeek) }
            if number(7) != nil { capabilities.insert(.canSetVolume) }
            let info = MediaInfo(
                sourceID: bundleID, bundleID: bundleID, sourceName: spotify ? "Spotify" : "Apple Music",
                itemID: [field(2), field(3), field(4)].compactMap { $0 }.joined(separator: " · "),
                title: field(2) ?? "曲名不可用", artist: field(3), album: field(4), duration: duration,
                currentPosition: position, playbackState: field(1) == "playing" ? .playing : .paused,
                volume: number(7).map { Float(min($0, 100) / 100) }, capabilities: capabilities
            )
            return (info, field(8).flatMap(URL.init(string:)))
        }
    }

    static func perform(_ action: MediaCommand, bundleID: String, value: Double?) -> Bool {
        guard isRunning(bundleID) else { return false }
        let command: String
        switch action {
        case .play: command = "play"
        case .pause: command = "pause"
        case .next: command = "next track"
        case .previous: command = "previous track"
        case .seek: command = "set player position to \(Int(value ?? 0))"
        case .volume: command = "set sound volume to \(Int((value ?? 0) * 100))"
        case .activate, .selectSource, .openPanel: return false
        }
        return execute(command + "\nreturn true", bundleID: bundleID)?.booleanValue == true
    }

    private static func isRunning(_ id: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    private static func execute(_ command: String, bundleID: String) -> NSAppleEventDescriptor? {
        let source = """
        with timeout of 1 second
            tell application id "\(bundleID)"
                \(command)
            end tell
        end timeout
        """
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
