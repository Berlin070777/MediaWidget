import Foundation
import AppKit

/// Controls media playback through MediaRemote commands (primary),
/// AppleScript menu clicking (fallback for NeteaseMusic),
/// and system volume via AppleScript.
class MediaController {
    private let bridge: MediaRemoteBridge?

    init(bridge: MediaRemoteBridge?) {
        self.bridge = bridge
    }

    // MARK: - MediaRemote Controls

    /// Toggle play/pause. Falls back to AppleScript for NeteaseMusic if MediaRemote fails.
    func togglePlayPause() {
        let success = bridge?.sendCommand(.togglePlayPause) ?? false
        if !success {
            neteaseMusicMenuClick("播放")
        }
    }

    /// Send play command via MediaRemote.
    func play() {
        let success = bridge?.sendCommand(.play) ?? false
        if !success {
            NSLog("[MediaController] Play command failed")
        }
    }

    /// Send pause command via MediaRemote.
    func pause() {
        let success = bridge?.sendCommand(.pause) ?? false
        if !success {
            NSLog("[MediaController] Pause command failed")
        }
    }

    /// Skip to next track. Falls back to AppleScript for NeteaseMusic if MediaRemote fails.
    func nextTrack() {
        let success = bridge?.sendCommand(.nextTrack) ?? false
        if !success {
            neteaseMusicMenuClick("下一个")
        }
    }

    /// Skip to previous track. Falls back to AppleScript for NeteaseMusic if MediaRemote fails.
    func previousTrack() {
        let success = bridge?.sendCommand(.previousTrack) ?? false
        if !success {
            neteaseMusicMenuClick("上一个")
        }
    }

    /// Seek to a specific time in seconds.
    func seek(to time: Double) {
        bridge?.setElapsedTime(time)
    }

    // MARK: - Volume Control (System-wide via AppleScript)

    /// Returns the current system output volume (0–100).
    func getSystemVolume() -> Int {
        let script = "output volume of (get volume settings)"
        guard let output = runAppleScript(script) else {
            return 50
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed) ?? 50
    }

    /// Sets the system output volume, clamped to 0–100.
    func setSystemVolume(_ volume: Int) {
        let clamped = min(max(volume, 0), 100)
        let script = "set volume output volume \(clamped)"
        _ = runAppleScript(script)
    }

    /// Returns whether the system audio output is currently muted.
    func isMuted() -> Bool {
        let script = "output muted of (get volume settings)"
        guard let output = runAppleScript(script) else {
            return false
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "true"
    }

    /// Toggles the system mute state.
    func toggleMute() {
        let currentlyMuted = isMuted()
        let newState = currentlyMuted ? "false" : "true"
        let script = "set volume output muted \(newState)"
        _ = runAppleScript(script)
    }

    // MARK: - AppleScript Fallback for NeteaseMusic

    /// Clicks a menu item in NeteaseMusic's "控制" menu via System Events.
    private func neteaseMusicMenuClick(_ menuItem: String) {
        let script = """
        tell application "System Events"
            tell process "NeteaseMusic"
                click menu item "\(menuItem)" of menu 1 of menu bar item "控制" of menu bar 1
            end tell
        end tell
        """
        _ = runAppleScript(script)
    }

    // MARK: - App Activation

    /// Activates (brings to front) the application with the given bundle identifier.
    func activateApp(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        }
    }

    // MARK: - Private Helpers

    /// Runs an AppleScript expression synchronously via `/usr/bin/osascript`.
    /// Returns the trimmed stdout on success, or `nil` on failure.
    @discardableResult
    private func runAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[MediaController] Failed to run AppleScript: %@", error.localizedDescription)
            return nil
        }

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "unknown error"
            NSLog("[MediaController] AppleScript error (status %d): %@",
                  process.terminationStatus, errorString)
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
