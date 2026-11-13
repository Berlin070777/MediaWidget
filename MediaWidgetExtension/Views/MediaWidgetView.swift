import SwiftUI
import WidgetKit

struct MediaWidgetView: View {
    let entry: MediaWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var media: MediaInfo { entry.mediaInfo }
    private var compact: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }

    var body: some View {
        Group {
            if media.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "play.circle").font(.title2).foregroundStyle(.secondary)
                    Text("未检测到媒体").font(.headline)
                    Text("打开 MediaWidget 并开始播放。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(URL(string: "mediawidget://panel"))
            } else {
                VStack(alignment: .leading, spacing: large ? 14 : 5) {
                    if compact {
                        metadata
                    } else {
                        HStack(spacing: large ? 13 : 9) {
                            if entry.showArtwork { artwork(size: large ? 96 : 43) }
                            metadata
                        }
                    }
                    if !compact { progress }
                    HStack(spacing: compact ? 12 : 26) {
                        Spacer(minLength: 0)
                        control(.previous, title: "上一项", icon: "backward.fill", size: 13)
                        control(media.isPlaying ? .pause : .play, title: media.isPlaying ? "暂停" : "播放",
                                icon: media.isPlaying ? "pause.fill" : "play.fill", size: large ? 24 : 17)
                        control(.next, title: "下一项", icon: "forward.fill", size: 13)
                        Spacer(minLength: 0)
                    }
                    if large {
                        Text("媒体音量 \(media.volume.map { "\(Int(($0 * 100).rounded()))%" } ?? "不可用")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var metadata: some View {
        Button(intent: WidgetPlaybackIntent(.activate, media: media)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(media.title).font(large ? .headline : .subheadline.bold()).lineLimit(large ? 2 : 1)
                Text(media.artist ?? "作者不可用").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(compact ? media.sourceName : "\(media.sourceName) · \(media.stateLabel)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开来源应用")
    }

    private var progress: some View {
        let position = media.position(at: entry.date)
        return VStack(spacing: 2) {
            if let duration = media.duration, duration > 0, let position {
                if media.isPlaying && media.playbackRate == 1 && position < duration {
                    let start = entry.date.addingTimeInterval(-position)
                    ProgressView(timerInterval: start...start.addingTimeInterval(duration), countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                } else {
                    ProgressView(value: position, total: duration)
                }
            }
            HStack {
                Text(MediaInfo.formatTime(position))
                Spacer()
                Text(MediaInfo.formatTime(media.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func control(_ action: WidgetPlaybackAction, title: String, icon: String, size: CGFloat) -> some View {
        Button(intent: WidgetPlaybackIntent(action, media: media)) {
            Image(systemName: icon).font(.system(size: size))
                .frame(minWidth: 30, minHeight: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(title)
        .invalidatableContent()
        .disabled(!(MediaCommand(rawValue: action.rawValue).map { media.capabilities.contains($0.capability) } ?? false))
    }

    private func artwork(size: CGFloat) -> some View {
        Group {
            if let data = media.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.secondary)
                }
                .accessibilityLabel("封面不可用")
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.14))
    }
}
