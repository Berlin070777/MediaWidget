// MenuBarView.swift
// MediaWidget
//
// Menu bar popover showing current media info and controls.

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: MediaMonitor

    /// System volume is read through `osascript`, which is slow (~50 ms).
    /// Cache it in `@State` and refresh only when something actually changed.
    @State private var systemVolume: Int = 50
    @State private var isMuted: Bool = false

    private var media: MediaInfo { monitor.currentMedia }

    private var controller: MediaController { MediaController(bridge: monitor.bridge) }

    var body: some View {
        VStack(spacing: 12) {
            headerSection
            Divider()

            if media.isEmpty {
                emptyStateSection
            } else {
                mediaInfoSection
                progressSection
                controlsSection
            }

            volumeSection
            Divider()
            footerSection
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            monitor.startMonitoring()
            refreshSystemAudio()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 6) {
            Image(systemName: media.isEmpty ? "hifispeaker" : media.sourceAppInfo.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text(media.isEmpty ? "未连接播放源" : media.sourceName)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Circle()
                .fill(media.isPlaying ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .help(media.isPlaying ? "正在播放" : "已暂停")
        }
    }

    // MARK: - Empty state

    private var emptyStateSection: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("打开任意播放器开始播放")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if monitor.bridge == nil {
                Text("MediaRemote 未加载，播放信息不可用")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Media Info

    private var mediaInfoSection: some View {
        HStack(spacing: 12) {
            ArtworkView(data: media.artworkData, size: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(media.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(media.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let album = media.album, !album.isEmpty {
                    Text(album)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, geometry.size.width * media.progress), height: 4)
                }
            }
            .frame(height: 4)

            HStack {
                Text(media.formattedCurrentPosition)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(media.formattedDuration)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 26) {
            Spacer()

            controlButton("backward.fill", size: 18, enabled: media.capabilities.canSkipPrevious) {
                controller.previousTrack()
                resync(after: 0.5)
            }

            Button {
                controller.togglePlayPause()
                resync(after: 0.3)
            } label: {
                Image(systemName: media.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)
            .disabled(!media.capabilities.canTogglePlayPause)

            controlButton("forward.fill", size: 18, enabled: media.capabilities.canSkipNext) {
                controller.nextTrack()
                resync(after: 0.5)
            }

            Spacer()
        }
    }

    private func controlButton(
        _ symbol: String,
        size: CGFloat,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(enabled ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Volume

    private var volumeSection: some View {
        HStack(spacing: 8) {
            Button {
                controller.toggleMute()
                refreshSystemAudio()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : volumeIcon(for: systemVolume))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .help(isMuted ? "取消静音" : "静音")

            Text("\(isMuted ? 0 : systemVolume)%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            Slider(
                value: Binding(
                    get: { Double(isMuted ? 0 : systemVolume) },
                    set: { newValue in
                        systemVolume = Int(newValue)
                        isMuted = false
                        controller.setSystemVolume(Int(newValue))
                    }
                ),
                in: 0...100
            )
            .controlSize(.mini)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 12) {
            if !media.isEmpty {
                Button {
                    controller.activateApp(bundleID: media.sourceID)
                } label: {
                    Label("打开应用", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button {
                (NSApp.delegate as? AppDelegate)?.presentFloatingPanel()
            } label: {
                Label("面板", systemImage: "macwindow.on.rectangle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            SettingsLink {
                Label("设置", systemImage: "gear")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    /// Refreshes MediaRemote state shortly after a command so the UI shows the result.
    private func resync(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            monitor.refreshNowPlaying()
        }
    }

    private func refreshSystemAudio() {
        let c = controller
        systemVolume = c.getSystemVolume()
        isMuted = c.isMuted()
    }

    private func volumeIcon(for vol: Int) -> String {
        switch vol {
        case 0:        return "speaker.fill"
        case 1..<33:   return "speaker.wave.1.fill"
        case 33..<66:  return "speaker.wave.2.fill"
        default:       return "speaker.wave.3.fill"
        }
    }
}

// MARK: - Artwork View

struct ArtworkView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.65), Color.accentColor.opacity(0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15, style: .continuous))
    }
}
