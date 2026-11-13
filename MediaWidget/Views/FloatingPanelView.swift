import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject private var monitor = MediaMonitor.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("媒体控制")
                    .font(.headline)
                Spacer()
                Button("设置", systemImage: "gearshape") { openSettings() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            PlayerControls(monitor: monitor, artworkSize: 76)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 36, leading: 18, bottom: 14, trailing: 18))
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .onAppear { monitor.refreshNowPlaying() }
    }
}

struct PlayerControls: View {
    @ObservedObject var monitor: MediaMonitor
    let artworkSize: CGFloat

    @State private var seekPosition: Double?
    @State private var mediaVolume: Double?
    @State private var systemVolume: Double?

    private var media: MediaInfo { monitor.currentMedia }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !monitor.allSources.isEmpty {
                Picker("播放源", selection: Binding(
                    get: { monitor.allSources.contains { $0.sourceID == monitor.preferredSource } ? monitor.preferredSource : "" },
                    set: { id in monitor.chooseSource(id) }
                )) {
                    Text("自动选择").tag("")
                    ForEach(monitor.allSources) { source in
                        Text("\(source.sourceName) · \(source.title)").tag(source.sourceID)
                    }
                }
                .pickerStyle(.menu)
            }

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
                            Text(media.title).font(.headline).lineLimit(2)
                            Text(media.artist ?? "作者不可用").foregroundStyle(.secondary).lineLimit(1)
                            if let album = media.album { Text(album).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                            Text("\(media.sourceName) · \(media.stateLabel)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开 \(media.sourceName)")

                TimelineView(.periodic(from: .now, by: media.isPlaying && media.currentPosition != nil ? 1 : 3600)) { context in
                    progress(position: media.position(at: context.date))
                }

                HStack(spacing: 24) {
                    Spacer()
                    control(.previous, "上一项", "backward.fill")
                    control(media.playPauseCommand, media.isPlaying ? "暂停" : "播放",
                            media.isPlaying ? "pause.circle.fill" : "play.circle.fill", size: 36)
                    control(.next, "下一项", "forward.fill")
                    Spacer()
                }

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
        .onChange(of: media.sourceID) { seekPosition = nil; mediaVolume = nil }
        .onChange(of: media.itemID) { seekPosition = nil; mediaVolume = nil }
    }

    private func progress(position: Double?) -> some View {
        VStack(spacing: 4) {
            if let duration = media.duration, duration > 0, let position {
                if media.capabilities.contains(.canSeek) {
                    Slider(value: Binding(get: { seekPosition ?? position }, set: { seekPosition = $0 }),
                           in: 0...duration, onEditingChanged: { editing in
                        guard !editing, let seekPosition else { return }
                        monitor.seek(seekPosition, for: media)
                        self.seekPosition = nil
                    })
                    .accessibilityLabel("播放进度")
                } else {
                    ProgressView(value: position, total: duration)
                }
            }
            HStack {
                Text("进度 \(MediaInfo.formatTime(seekPosition ?? position))")
                Spacer()
                Text("时长 \(MediaInfo.formatTime(media.duration))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func control(_ action: MediaCommand, _ title: String, _ icon: String, size: CGFloat = 17) -> some View {
        Button { monitor.submit(action, for: media) } label: {
            Image(systemName: icon).font(.system(size: size)).frame(minWidth: 24, minHeight: 24)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .help(title)
        .disabled(!media.capabilities.contains(action.capability))
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
