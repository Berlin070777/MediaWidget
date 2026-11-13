import Foundation

enum BrowserKind: String, Codable, Sendable {
    case chrome, safari

    var bundleID: String {
        switch self {
        case .chrome: Constants.KnownApp.chrome
        case .safari: Constants.KnownApp.safari
        }
    }

    var snapshotLifetime: TimeInterval { self == .safari ? 60 : 16 }

    var name: String { self == .safari ? "Safari · B站" : "Chrome · B站" }

    var directory: URL? {
        switch self {
        case .chrome:
            return FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/MediaWidget/Chrome")
        case .safari:
            let group = Constants.appGroupID
            guard !group.isEmpty else { return nil }
            return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
                .appending(path: "Browser/Safari")
        }
    }

    static func kind(for sourceID: String) -> Self? {
        if sourceID.hasPrefix("chrome:") { return .chrome }
        if sourceID.hasPrefix("safari:") { return .safari }
        return nil
    }
}

struct BrowserMedia: Codable, Sendable {
    let itemID: String
    let title: String
    let artist: String
    let artwork: URL?
    let duration: Double?
    let position: Double?
    let rate: Double?
    let playing: Bool
    let volume: Float?
    let canSeek: Bool

    var isValid: Bool {
        itemID.count <= 100 && (itemID.hasPrefix("/video/") || itemID.hasPrefix("/bangumi/play/"))
            && title.count <= 300 && artist.count <= 300
    }

    func mediaInfo(browser: BrowserKind, key: String, timestamp: Date) -> MediaInfo {
        let duration = duration.flatMap { (0.0..<1_000_000).contains($0) && $0 > 0 ? $0 : nil }
        let position = position.flatMap { (0.0..<1_000_000).contains($0) ? $0 : nil }
        var capabilities: MediaCapabilities = [.canPlay, .canPause, .canSetVolume]
        if canSeek && duration != nil { capabilities.insert(.canSeek) }
        return MediaInfo(
            sourceID: "\(browser.rawValue):\(key)", bundleID: browser.bundleID,
            sourceName: browser.name, itemID: itemID, title: title.nonBlank ?? "视频标题不可用",
            artist: artist.nonBlank, duration: duration, currentPosition: position,
            playbackState: playing ? .playing : .paused,
            playbackRate: rate.flatMap { (0.05...16).contains($0) ? $0 : nil } ?? 1,
            volume: volume.flatMap { (0...1).contains($0) ? $0 : nil },
            capabilities: capabilities, lastUpdated: timestamp
        )
    }
}

struct BrowserCommand: Codable, Sendable {
    let itemID: String
    let action: MediaCommand
    let value: Double?
    let issuedAt: Date
}

enum BrowserBridge {
    private struct Request: Decodable {
        let documentID: UUID
        let requestID: UUID?
        let state: BrowserMedia?
    }

    struct Response: Encodable {
        var requestID: UUID?
        var command: BrowserCommand?
    }

    struct Record: Codable, Sendable {
        let state: BrowserMedia
        let timestamp: Date
    }

    static func receive(_ data: Data, from browser: BrowserKind, profile: UUID? = nil) -> Response {
        guard data.count <= 8192, let directory = browser.directory,
              let request = try? JSONDecoder().decode(Request.self, from: data) else { return Response() }
        let response = Response(requestID: request.requestID)
        let key = [profile, request.documentID].compactMap { $0?.uuidString }.joined(separator: "-")
        let file = directory.appending(path: key + ".json")
        guard let state = request.state, state.isValid else {
            try? FileManager.default.removeItem(at: file)
            return response
        }
        do {
            try write(Record(state: state, timestamp: .now), to: file)
        } catch { return response }

        let mailbox = directory.appending(path: key + ".command")
        let claimed = directory.appending(path: UUID().uuidString + ".inflight")
        guard (try? FileManager.default.moveItem(at: mailbox, to: claimed)) != nil else { return response }
        defer { try? FileManager.default.removeItem(at: claimed) }
        let command: BrowserCommand? = read(claimed)
        guard let command, command.itemID == state.itemID,
              abs(command.issuedAt.timeIntervalSinceNow) < 10 else { return response }
        return Response(requestID: request.requestID, command: command)
    }

    static func snapshots(_ browser: BrowserKind) -> [(MediaInfo, URL?)] {
        guard let directory = browser.directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        let now = Date.now
        return files.compactMap { file in
            if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               now.timeIntervalSince(modified) > 300 {
                try? FileManager.default.removeItem(at: file)
                return nil
            }
            guard file.pathExtension == "json",
                  let record: Record = read(file),
                  abs(now.timeIntervalSince(record.timestamp)) < browser.snapshotLifetime,
                  record.state.isValid else { return nil }
            let key = file.deletingPathExtension().lastPathComponent
            return (record.state.mediaInfo(browser: browser, key: key, timestamp: record.timestamp), record.state.artwork)
        }
    }

    static func send(_ command: MediaCommand, to media: MediaInfo, value: Double?) -> Bool {
        guard let browser = BrowserKind.kind(for: media.sourceID), let directory = browser.directory,
              let itemID = media.itemID, abs(media.lastUpdated.timeIntervalSinceNow) < browser.snapshotLifetime else { return false }
        let key = String(media.sourceID.dropFirst(browser.rawValue.count + 1))
        guard key.count <= 73, key.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return false }
        let file = directory.appending(path: key + ".command")
        do {
            try write(BrowserCommand(itemID: itemID, action: command, value: value, issuedAt: .now), to: file)
            return true
        } catch { return false }
    }

    private static func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url), data.count <= 8192 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
