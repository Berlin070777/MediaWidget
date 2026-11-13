import AppIntents
import Foundation
import os

enum WidgetPlaybackAction: String, AppEnum {
    case play, pause, next, previous, activate
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "媒体操作"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .play: "播放", .pause: "暂停", .next: "下一项", .previous: "上一项", .activate: "打开来源"
    ]
}

struct WidgetPlaybackIntent: AppIntent {
    private static let logger = Logger(subsystem: "com.mediawidget.app", category: "WidgetCommand")
    static let title: LocalizedStringResource = "控制媒体"
    static let description = IntentDescription("控制小组件上显示的媒体来源")
    static let isDiscoverable = false

    @Parameter(title: "来源") var source: String
    @Parameter(title: "媒体") var item: String?
    @Parameter(title: "操作") var action: WidgetPlaybackAction

    init() {}

    init(_ action: WidgetPlaybackAction, media: MediaInfo) {
        self.action = action
        source = media.sourceID
        item = media.itemID
    }

    func perform() async throws -> some IntentResult {
        let store = SharedDefaults.shared
        Self.logger.notice("Widget intent invoked: \(self.action.rawValue, privacy: .public)")
        guard let command = MediaCommand(rawValue: action.rawValue),
              let snapshot = store.snapshot(), snapshot.isFresh,
              snapshot.media.sourceID == source, snapshot.media.itemID == item,
              snapshot.media.capabilities.contains(command.capability) else {
            Self.logger.notice("Widget intent ignored because the snapshot or target was stale")
            store.requestWidgetReload()
            return .result()
        }
        let request = WidgetCommand(id: UUID(), sourceID: source, itemID: item, action: command, issuedAt: .now)
        do {
            try store.enqueue(request)
            Self.logger.notice("Widget command enqueued")
        } catch {
            Self.logger.error("Widget command write failed: \(error.localizedDescription, privacy: .private)")
            throw error
        }
        // Give the resident app time to publish the resulting state before WidgetKit
        // asks for the next timeline. The browser bridge can take a heartbeat.
        if command == .play || command == .pause {
            let expected: PlaybackState = command == .play ? .playing : .paused
            for _ in 0..<14 {
                if let current = store.snapshot()?.media,
                   current.sourceID != source || current.itemID != item || current.playbackState == expected { break }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        return .result()
    }
}
