import Foundation
import WidgetKit

struct WidgetSourceSummary: Codable, Hashable, Identifiable, Sendable {
    let sourceID: String
    let bundleID: String
    let name: String
    let title: String
    let isPlaying: Bool
    var id: String { sourceID }
}

struct WidgetSnapshot: Codable {
    let media: MediaInfo
    let writtenAt: Date
    let showArtwork: Bool
    let sources: [WidgetSourceSummary]
    let preferredSource: String

    static let maxAge: TimeInterval = 90
    var isFresh: Bool { abs(writtenAt.timeIntervalSinceNow) < Self.maxAge }

    init(media: MediaInfo, writtenAt: Date, showArtwork: Bool,
         sources: [WidgetSourceSummary] = [], preferredSource: String = "") {
        self.media = media
        self.writtenAt = writtenAt
        self.showArtwork = showArtwork
        self.sources = sources
        self.preferredSource = preferredSource
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        media = try container.decode(MediaInfo.self, forKey: .media)
        writtenAt = try container.decode(Date.self, forKey: .writtenAt)
        showArtwork = try container.decode(Bool.self, forKey: .showArtwork)
        sources = try container.decodeIfPresent([WidgetSourceSummary].self, forKey: .sources) ?? []
        preferredSource = try container.decodeIfPresent(String.self, forKey: .preferredSource) ?? ""
    }
}

struct WidgetCommand: Codable {
    let id: UUID
    let sourceID: String
    let itemID: String?
    let action: MediaCommand
    let issuedAt: Date
}

struct SharedDefaults: Sendable {
    static let shared = SharedDefaults()
    let groupURL: URL?
    let directory: URL

    init() {
        let files = FileManager.default
        let group = Constants.appGroupID
        groupURL = group.isEmpty ? nil : files.containerURL(forSecurityApplicationGroupIdentifier: group)
        let support: URL
        if let groupURL {
            support = groupURL
        } else if Bundle.main.bundleIdentifier == Constants.widgetBundleID,
                  let sandboxSupport = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            support = sandboxSupport
        } else {
            support = files.homeDirectoryForCurrentUser.appending(path:
                "Library/Containers/\(Constants.widgetBundleID)/Data/Library/Application Support")
        }
        directory = support.appending(path: "MediaWidget", directoryHint: .isDirectory)
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        try Self.write(snapshot, to: directory.appending(path: "Snapshot-v2.json"))
    }

    func snapshot() -> WidgetSnapshot? {
        Self.read(WidgetSnapshot.self, from: directory.appending(path: "Snapshot-v2.json"))
    }

    func enqueue(_ command: WidgetCommand) throws {
        try Self.write(command, to: commandDirectory.appending(path: "\(command.id.uuidString).json"))
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(Constants.commandNotification as CFString),
            nil, nil, true
        )
    }

    func takeCommands() -> [WidgetCommand] {
        let files = FileManager.default
        let pending = (try? files.contentsOfDirectory(at: commandDirectory, includingPropertiesForKeys: nil)) ?? []
        return pending.filter { $0.pathExtension == "json" }.compactMap { url in
            let command = Self.read(WidgetCommand.self, from: url)
            try? files.removeItem(at: url)
            return command
        }.filter { abs($0.issuedAt.timeIntervalSinceNow) < 10 }
            .sorted { $0.issuedAt < $1.issuedAt }
    }

    func requestWidgetReload() {
        WidgetCenter.shared.reloadTimelines(ofKind: Constants.widgetKind)
    }

    private var commandDirectory: URL { directory.appending(path: "WidgetCommands") }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
