import AppKit
import SwiftUI

@MainActor
@Observable
final class MediaWindowNavigation {
    enum Page { case albums, player }

    var page: Page = .albums
    var isChoosingSource = false
    var isSearchingAlbums = false
    var albumFocus: AlbumWallFocus?
}

struct MediaWindowView: View {
    @ObservedObject var monitor: MediaMonitor
    @Bindable var navigation: MediaWindowNavigation
    let input: AlbumWallInput

    var body: some View {
        Group {
            switch navigation.page {
            case .albums:
                AlbumWallView(monitor: monitor, library: AlbumWallStore.shared, input: input, navigation: navigation)
            case .player:
                ScrollView {
                    PlayerControls(monitor: monitor, artworkSize: 88, isChoosingSource: $navigation.isChoosingSource,
                                   usesGlass: true)
                        .frame(maxWidth: 490)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .background { MediaWindowBackdrop() }
    }
}

struct PlayerControls: View {
    @ObservedObject var monitor: MediaMonitor
    let artworkSize: CGFloat
    @Binding var isChoosingSource: Bool
    var usesGlass = false

    @State private var mediaVolume: Double?
    @State private var systemVolume: Double?

    private var media: MediaInfo { monitor.currentMedia }

    var body: some View {
        if isChoosingSource {
            PlaybackSourcePicker(monitor: monitor, isPresented: $isChoosingSource)
                .padding(usesGlass ? 16 : 0)
                .mediaGlass(in: RoundedRectangle(cornerRadius: 21), enabled: usesGlass)
        } else {
            controls
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: usesGlass ? 17 : 12) {
            Button {
                clearDrafts()
                isChoosingSource = true
                monitor.refreshNowPlaying()
            } label: {
                HStack(spacing: 7) {
                    Label("播放源", systemImage: "rectangle.on.rectangle")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 8)
                    Text(monitor.preferredSource.isEmpty ? "自动选择" : media.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, usesGlass ? 14 : 10)
                .frame(height: usesGlass ? 36 : 30)
                .background(.primary.opacity(usesGlass ? 0 : 0.07), in: RoundedRectangle(cornerRadius: 8))
                .mediaGlass(in: Capsule(), enabled: usesGlass)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择播放源")
            .accessibilityValue(monitor.preferredSource.isEmpty ? "自动选择" : media.sourceName)

            if media.isEmpty {
                Text(media.title).font(.headline)
                Text("播放媒体，或在设置中检查权限和浏览器扩展。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button { monitor.submit(.activate, for: media) } label: {
                    HStack(spacing: 12) {
                        if monitor.showArtwork {
                            ArtworkView(data: media.artworkData, size: artworkSize)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(media.title).font(usesGlass ? .title2.weight(.semibold) : .headline).lineLimit(2)
                            Text(media.artist ?? "作者不可用").foregroundStyle(.secondary).lineLimit(1)
                            if let album = media.album { Text(album).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                            Text("\(media.sourceName) · \(media.stateLabel)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, usesGlass ? 4 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开 \(media.sourceName)")

                PlaybackProgress(media: media, seek: { monitor.seek($0, for: media) })

                PlaybackTransportControls(media: media, submit: { monitor.submit($0, for: media) })
                    .padding(.horizontal, usesGlass ? 21 : 0)
                    .padding(.vertical, usesGlass ? 7 : 0)
                    .mediaGlass(in: Capsule(), enabled: usesGlass)
                    .frame(maxWidth: .infinity)

                volumeRow("媒体音量", value: media.volume, draft: $mediaVolume,
                          enabled: media.capabilities.contains(.canSetVolume)) { value in
                    monitor.setMediaVolume(value, for: media)
                }
            }

            volumeRow(monitor.systemAudio.muted == true ? "系统音量（静音）" : "系统音量",
                      value: monitor.systemAudio.volume, draft: $systemVolume,
                      enabled: monitor.systemAudio.canSetVolume, commit: { value in monitor.setSystemVolume(value) })

            if monitor.systemAudio.canMute {
                Button(monitor.systemAudio.muted == true ? "取消静音" : "静音系统输出",
                       systemImage: monitor.systemAudio.muted == true ? "speaker.wave.2" : "speaker.slash") {
                    monitor.toggleSystemMute()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if let error = monitor.errorMessage {
                Text(error).foregroundStyle(.orange).font(.caption)
            }
        }
        .onChange(of: media.sourceID) { clearDrafts() }
        .onChange(of: media.itemID) { clearDrafts() }
    }

    private func clearDrafts() {
        mediaVolume = nil
    }

    private func volumeRow(_ title: String, value: Float?, draft: Binding<Double?>,
                           enabled: Bool, commit: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title)
            if let value, enabled {
                Slider(value: Binding(get: { draft.wrappedValue ?? Double(value) }, set: { draft.wrappedValue = $0 }),
                       in: 0...1, onEditingChanged: { editing in
                    guard !editing, let pending = draft.wrappedValue else { return }
                    commit(pending)
                    draft.wrappedValue = nil
                })
                .accessibilityLabel(title)
            } else {
                Spacer()
            }
            Text(value.map { "\(Int(((draft.wrappedValue ?? Double($0)) * 100).rounded()))%" } ?? "不可用")
                .monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

struct PlaybackTransportControls: View {
    let media: MediaInfo
    var compact = false
    let submit: (MediaCommand) -> Void

    var body: some View {
        HStack(spacing: compact ? 4 : 18) {
            control(.previous, title: "上一首", icon: "backward.end.fill")
            control(media.playPauseCommand, title: media.isPlaying ? "暂停" : "播放",
                    icon: media.isPlaying ? "pause.circle.fill" : "play.circle.fill", primary: true)
            control(.next, title: "下一首", icon: "forward.end.fill")
        }
        .fixedSize()
    }

    private func control(_ action: MediaCommand, title: String, icon: String, primary: Bool = false) -> some View {
        let symbolSize: CGFloat = primary ? (compact ? 24 : 36) : (compact ? 13 : 17)
        return Button {
            submit(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: symbolSize))
                .frame(minWidth: compact ? 30 : 24, minHeight: compact ? 32 : 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .help(title)
        .disabled(!media.capabilities.contains(action.capability))
    }
}

struct PlaybackProgress: View {
    let media: MediaInfo
    var compact = false
    let seek: (TimeInterval) -> Void

    var body: some View {
        PlaybackProgressTrack(media: media, compact: compact, seek: seek)
            .id(ScrubTarget(source: media.sourceID, item: media.itemID, title: media.title))
    }
}

private struct PlaybackProgressTrack: View {
    let media: MediaInfo
    let compact: Bool
    let seek: (TimeInterval) -> Void
    @State private var draft: TimeInterval?

    var body: some View {
        TimelineView(.periodic(from: .now, by: media.isPlaying && media.currentPosition != nil ? 1 : 3600)) { context in
            let position = media.position(at: context.date)
            if compact {
                HStack(spacing: 12) {
                    Text(MediaInfo.formatTime(draft ?? position))
                    track(position: position)
                    Text(MediaInfo.formatTime(media.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    track(position: position)
                    HStack {
                        Text("进度 \(MediaInfo.formatTime(draft ?? position))")
                        Spacer()
                        Text("时长 \(MediaInfo.formatTime(media.duration))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func track(position: TimeInterval?) -> some View {
        if let duration = media.duration, duration.isFinite, duration > 0, let position, position.isFinite {
            if media.capabilities.contains(.canSeek) {
                PlaybackScrubber(position: position, duration: duration) { draft = $0 } commit: { value in
                    draft = nil
                    seek(value)
                }
            } else {
                ProgressView(value: position, total: duration)
                    .tint(.secondary)
                    .accessibilityLabel("播放进度")
            }
        } else if compact {
            Capsule()
                .fill(.secondary.opacity(0.21))
                .frame(height: 3)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("播放进度不可用")
        }
    }
}

private struct ScrubTarget: Hashable {
    let source: String
    let item: String?
    let title: String
}

private struct PlaybackScrubber: NSViewRepresentable {
    let position: TimeInterval
    let duration: TimeInterval
    let preview: (TimeInterval) -> Void
    let commit: (TimeInterval) -> Void

    func makeNSView(context: Context) -> Scrubber {
        let slider = Scrubber()
        slider.minValue = 0
        slider.isContinuous = true
        slider.target = slider
        slider.action = #selector(Scrubber.changed)
        slider.setAccessibilityLabel("播放进度")
        return slider
    }

    func updateNSView(_ slider: Scrubber, context: Context) {
        slider.preview = preview
        slider.commit = commit
        if !slider.trackingDrag {
            slider.maxValue = duration
            slider.doubleValue = position
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Scrubber, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }

    final class Scrubber: NSSlider {
        private(set) var trackingDrag = false
        var preview: ((TimeInterval) -> Void)?
        var commit: ((TimeInterval) -> Void)?

        override func mouseDown(with event: NSEvent) {
            let commit = self.commit
            trackingDrag = true
            super.mouseDown(with: event)
            trackingDrag = false
            commit?(doubleValue)
        }

        @objc func changed() {
            if trackingDrag {
                preview?(doubleValue)
            } else {
                commit?(doubleValue)
            }
        }
    }
}
