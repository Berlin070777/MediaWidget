// MediaRemoteBridge.swift
// MediaWidget
//
// Swift-friendly wrapper around the private MediaRemote framework.
// Loads symbols dynamically at runtime via CFBundle so no private headers are needed.

import Foundation
import AppKit

// MARK: - MRCommand Enum

/// Maps friendly command names to the UInt32 values expected by MRMediaRemoteSendCommand.
enum MRCommand: UInt32, Sendable {
    case play               = 0
    case pause              = 1
    case togglePlayPause    = 2
    case stop               = 3
    case nextTrack          = 4
    case previousTrack      = 5
    case toggleShuffle      = 6
    case toggleRepeat       = 7
    case startForwardSeek   = 8
    case endForwardSeek     = 9
    case startBackwardSeek  = 10
    case endBackwardSeek    = 11
    case goBackFifteenSeconds = 12
    case goForwardFifteenSeconds = 13
    case goBackThirtySeconds = 14
    case goForwardThirtySeconds = 15
    case skipForward        = 17
    case skipBackward       = 18
    case changePlaybackRate = 20
    case likeTrack          = 21
    case dislikeTrack       = 22
    case bookmarkTrack      = 23
}

// MARK: - MediaRemoteBridge

/// Dynamically loads and wraps the private MediaRemote framework.
/// Thread-safe by virtue of immutable function-pointer storage after init.
final class MediaRemoteBridge: @unchecked Sendable {

    // MARK: - Function-pointer typedefs

    private typealias GetNowPlayingInfoFunc =
        @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetNowPlayingAppPIDFunc =
        @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    private typealias GetIsPlayingFunc =
        @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias SendCommandFunc =
        @convention(c) (UInt32, UnsafeRawPointer?) -> Bool
    private typealias RegisterForNotificationsFunc =
        @convention(c) (DispatchQueue) -> Void
    private typealias SetElapsedTimeFunc =
        @convention(c) (Double) -> Void
    private typealias GetSupportedCommandsFunc =
        @convention(c) (DispatchQueue, @escaping (NSArray) -> Void) -> Void

    // MARK: - Cached function pointers

    private let getNowPlayingInfoPtr: GetNowPlayingInfoFunc
    private let getNowPlayingAppPIDPtr: GetNowPlayingAppPIDFunc
    private let getIsPlayingPtr: GetIsPlayingFunc
    private let sendCommandPtr: SendCommandFunc
    private let registerForNotificationsPtr: RegisterForNotificationsFunc
    private let setElapsedTimePtr: SetElapsedTimeFunc
    private let getSupportedCommandsPtr: GetSupportedCommandsFunc

    // MARK: - Info dictionary keys

    let kNowPlayingInfoTitle: String
    let kNowPlayingInfoArtist: String
    let kNowPlayingInfoAlbum: String
    let kNowPlayingInfoArtworkData: String
    let kNowPlayingInfoArtworkMIMEType: String
    let kNowPlayingInfoDuration: String
    let kNowPlayingInfoElapsedTime: String
    let kNowPlayingInfoPlaybackRate: String
    let kNowPlayingInfoTimestamp: String
    let kNowPlayingInfoContentItemIdentifier: String
    let kNowPlayingInfoArtworkDataWidth: String
    let kNowPlayingInfoArtworkDataHeight: String
    let kNowPlayingInfoArtworkIdentifier: String

    // MARK: - Notification names

    let nowPlayingInfoDidChangeNotification: Notification.Name
    let nowPlayingApplicationDidChangeNotification: Notification.Name
    let nowPlayingApplicationIsPlayingDidChangeNotification: Notification.Name

    // MARK: - Observation tokens

    private var observationTokens: [NSObjectProtocol] = []
    private let observationLock = NSLock()

    // MARK: - Initializer

    /// Loads the MediaRemote private framework and resolves all required symbols.
    /// Returns `nil` if the framework cannot be loaded or any symbol is missing.
    init?() {
        // Build a URL to the private framework bundle.
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let frameworkURL = CFURLCreateWithFileSystemPath(
            kCFAllocatorDefault,
            frameworkPath as CFString,
            .cfurlposixPathStyle,
            true
        ) else {
            return nil
        }

        // Load the bundle.
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, frameworkURL) else {
            return nil
        }

        // Ensure the bundle's code is loaded into the process.
        var isLoaded = false
        isLoaded = CFBundleLoadExecutable(bundle)
        guard isLoaded else {
            return nil
        }

        // Helper: resolve a C function pointer from the bundle.
        func loadFunc<T>(_ name: String) -> T? {
            guard let ptr = CFBundleGetFunctionPointerForName(bundle, name as CFString) else {
                return nil
            }
            return unsafeBitCast(ptr, to: T.self)
        }

        // Helper: resolve a data pointer (CFStringRef) from the bundle and return as Swift String.
        func loadStringConstant(_ name: String) -> String? {
            guard let ptr = CFBundleGetDataPointerForName(bundle, name as CFString) else {
                return nil
            }
            // The data pointer points to a CFStringRef (i.e. a pointer-to-pointer pattern).
            let cfStringRef = ptr.assumingMemoryBound(to: CFString.self).pointee
            return cfStringRef as String
        }

        // ---------------------------------------------------------------
        // Load function pointers
        // ---------------------------------------------------------------

        guard let f1: GetNowPlayingInfoFunc = loadFunc("MRMediaRemoteGetNowPlayingInfo"),
              let f2: GetNowPlayingAppPIDFunc = loadFunc("MRMediaRemoteGetNowPlayingApplicationPID"),
              let f3: GetIsPlayingFunc = loadFunc("MRMediaRemoteGetNowPlayingApplicationIsPlaying"),
              let f4: SendCommandFunc = loadFunc("MRMediaRemoteSendCommand"),
              let f5: RegisterForNotificationsFunc = loadFunc("MRMediaRemoteRegisterForNowPlayingNotifications"),
              let f6: SetElapsedTimeFunc = loadFunc("MRMediaRemoteSetElapsedTime"),
              let f7: GetSupportedCommandsFunc = loadFunc("MRMediaRemoteGetSupportedCommands")
        else {
            return nil
        }

        self.getNowPlayingInfoPtr = f1
        self.getNowPlayingAppPIDPtr = f2
        self.getIsPlayingPtr = f3
        self.sendCommandPtr = f4
        self.registerForNotificationsPtr = f5
        self.setElapsedTimePtr = f6
        self.getSupportedCommandsPtr = f7

        // ---------------------------------------------------------------
        // Load info-dictionary key strings
        // ---------------------------------------------------------------

        guard let kTitle = loadStringConstant("kMRMediaRemoteNowPlayingInfoTitle"),
              let kArtist = loadStringConstant("kMRMediaRemoteNowPlayingInfoArtist"),
              let kAlbum = loadStringConstant("kMRMediaRemoteNowPlayingInfoAlbum"),
              let kArtworkData = loadStringConstant("kMRMediaRemoteNowPlayingInfoArtworkData"),
              let kArtworkMIME = loadStringConstant("kMRMediaRemoteNowPlayingInfoArtworkMIMEType"),
              let kDuration = loadStringConstant("kMRMediaRemoteNowPlayingInfoDuration"),
              let kElapsedTime = loadStringConstant("kMRMediaRemoteNowPlayingInfoElapsedTime"),
              let kPlaybackRate = loadStringConstant("kMRMediaRemoteNowPlayingInfoPlaybackRate"),
              let kTimestamp = loadStringConstant("kMRMediaRemoteNowPlayingInfoTimestamp"),
              let kContentItemID = loadStringConstant("kMRMediaRemoteNowPlayingInfoContentItemIdentifier"),
              let kArtworkWidth = loadStringConstant("kMRMediaRemoteNowPlayingInfoArtworkDataWidth"),
              let kArtworkHeight = loadStringConstant("kMRMediaRemoteNowPlayingInfoArtworkDataHeight"),
              let kArtworkID = loadStringConstant("kMRMediaRemoteNowPlayingInfoArtworkIdentifier")
        else {
            return nil
        }

        self.kNowPlayingInfoTitle = kTitle
        self.kNowPlayingInfoArtist = kArtist
        self.kNowPlayingInfoAlbum = kAlbum
        self.kNowPlayingInfoArtworkData = kArtworkData
        self.kNowPlayingInfoArtworkMIMEType = kArtworkMIME
        self.kNowPlayingInfoDuration = kDuration
        self.kNowPlayingInfoElapsedTime = kElapsedTime
        self.kNowPlayingInfoPlaybackRate = kPlaybackRate
        self.kNowPlayingInfoTimestamp = kTimestamp
        self.kNowPlayingInfoContentItemIdentifier = kContentItemID
        self.kNowPlayingInfoArtworkDataWidth = kArtworkWidth
        self.kNowPlayingInfoArtworkDataHeight = kArtworkHeight
        self.kNowPlayingInfoArtworkIdentifier = kArtworkID

        // ---------------------------------------------------------------
        // Load notification name strings
        // ---------------------------------------------------------------

        guard let nInfoChanged = loadStringConstant("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
              let nAppChanged = loadStringConstant("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
              let nPlayingChanged = loadStringConstant("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
        else {
            return nil
        }

        self.nowPlayingInfoDidChangeNotification = Notification.Name(nInfoChanged)
        self.nowPlayingApplicationDidChangeNotification = Notification.Name(nAppChanged)
        self.nowPlayingApplicationIsPlayingDidChangeNotification = Notification.Name(nPlayingChanged)
    }

    deinit {
        removeAllObservations()
    }

    // MARK: - Public API

    /// Registers with the system to begin receiving now-playing notifications.
    /// Must be called before `observeNowPlayingChanges(handler:)` will fire.
    func registerForNotifications() {
        registerForNotificationsPtr(DispatchQueue.main)
    }

    /// Asynchronously fetches the current now-playing info dictionary.
    func getNowPlayingInfo(completion: @escaping ([String: Any]) -> Void) {
        getNowPlayingInfoPtr(DispatchQueue.main, completion)
    }

    /// Asynchronously fetches the PID of the now-playing application.
    func getNowPlayingAppPID(completion: @escaping (Int32) -> Void) {
        getNowPlayingAppPIDPtr(DispatchQueue.main, completion)
    }

    /// Asynchronously queries whether the now-playing application is currently playing.
    func getIsPlaying(completion: @escaping (Bool) -> Void) {
        getIsPlayingPtr(DispatchQueue.main, completion)
    }

    /// Sends a media remote command to the now-playing application.
    /// - Returns: `true` if the command was accepted.
    @discardableResult
    func sendCommand(_ command: MRCommand) -> Bool {
        return sendCommandPtr(command.rawValue, nil)
    }

    /// Sets the playback elapsed time (seek).
    func setElapsedTime(_ time: Double) {
        setElapsedTimePtr(time)
    }

    /// Asynchronously fetches the list of supported commands from the now-playing app.
    func getSupportedCommands(completion: @escaping (NSArray) -> Void) {
        getSupportedCommandsPtr(DispatchQueue.main, completion)
    }

    /// Registers a handler that fires whenever any now-playing state changes
    /// (info, application, or is-playing). The handler is always called on the main queue.
    ///
    /// Calling this multiple times adds additional handlers. All handlers are removed on deinit.
    func observeNowPlayingChanges(handler: @escaping () -> Void) {
        let center = NotificationCenter.default

        let names: [Notification.Name] = [
            nowPlayingInfoDidChangeNotification,
            nowPlayingApplicationDidChangeNotification,
            nowPlayingApplicationIsPlayingDidChangeNotification
        ]

        observationLock.lock()
        for name in names {
            let token = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                handler()
            }
            observationTokens.append(token)
        }
        observationLock.unlock()
    }

    /// Removes all registered observation tokens.
    func removeAllObservations() {
        observationLock.lock()
        let tokens = observationTokens
        observationTokens.removeAll()
        observationLock.unlock()

        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
    }
}
