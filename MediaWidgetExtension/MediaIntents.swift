// MediaIntents.swift
// MediaWidgetExtension
//
// AppIntents for widget button interactions. These intents load the private
// MediaRemote framework directly (the widget extension runs in a separate process
// and cannot access the main app's MediaMonitor).

import AppIntents
import WidgetKit

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Shared Helpers

/// Sends a MediaRemote command by loading the framework in-process.
/// Reloads the widget timeline after sending.
private func sendMediaRemoteCommand(_ commandValue: UInt32) {
    typealias SendCommandFunc = @convention(c) (UInt32, UnsafeRawPointer?) -> Bool

    let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
    guard let frameworkURL = CFURLCreateWithFileSystemPath(
        kCFAllocatorDefault,
        frameworkPath as CFString,
        .cfurlposixPathStyle,
        true
    ) else { return }

    guard let bundle = CFBundleCreate(kCFAllocatorDefault, frameworkURL) else { return }
    guard CFBundleLoadExecutable(bundle) else { return }

    guard let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else {
        return
    }

    let sendCommand = unsafeBitCast(ptr, to: SendCommandFunc.self)
    _ = sendCommand(commandValue, nil)

    // Give the system a moment to update now-playing info, then reload.
    WidgetCenter.shared.reloadTimelines(ofKind: Constants.WidgetKind.mediaControl)
}

// MARK: - Toggle Play/Pause Intent

struct TogglePlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "播放/暂停"
    static let description: IntentDescription = IntentDescription("切换播放/暂停状态")

    func perform() async throws -> some IntentResult {
        sendMediaRemoteCommand(Constants.MediaRemoteCommand.togglePlayPause)
        return .result()
    }
}

// MARK: - Next Track Intent

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "下一曲"
    static let description: IntentDescription = IntentDescription("跳到下一首曲目")

    func perform() async throws -> some IntentResult {
        sendMediaRemoteCommand(Constants.MediaRemoteCommand.nextTrack)
        return .result()
    }
}

// MARK: - Previous Track Intent

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "上一曲"
    static let description: IntentDescription = IntentDescription("跳到上一首曲目")

    func perform() async throws -> some IntentResult {
        sendMediaRemoteCommand(Constants.MediaRemoteCommand.previousTrack)
        return .result()
    }
}

// MARK: - Open Source App Intent

struct OpenSourceAppIntent: AppIntent {
    static let title: LocalizedStringResource = "打开来源应用"
    static let description: IntentDescription = IntentDescription("打开正在播放媒体的应用")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Bundle ID")
    var bundleID: String

    init() {
        self.bundleID = ""
    }

    init(bundleID: String) {
        self.bundleID = bundleID
    }

    func perform() async throws -> some IntentResult {
        #if canImport(AppKit)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        #endif
        return .result()
    }
}
