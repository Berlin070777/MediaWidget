// FloatingPanelView.swift
// MediaWidget
//
// A standalone floating panel with full media controls: draggable progress,
// system volume slider and source switching.

import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject private var monitor = MediaMonitor.shared

    @Environment(\.openSettings) private var openSettings

    @State private var seekPosition: Double?
    @State private var volumeLevel: Double = 50
    @State private var isMuted = false

    private var media: MediaInfo { monitor.currentMedia }
    private var controller: MediaController { MediaController(bridge: monitor.bridge) }

    var body: some View {
        VStack(spacing: 14) {
            header
            mediaRow

            if !media.isEmpty {
                progressSection
                controls
            }

            volumeSection

            if !media.isEmpty {
                openAppButton
            }
        }
        // Leave room for the native traffic lights in the title bar.
        .padding(EdgeInsets(top: 32, leading: 18, bottom: 18, trailing: 18))
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .onAppear(perform: syncSystemAudio)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: media.isEmpty ? "hifispeaker" : media.sourceAppInfo.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(media.isEmpty ? "未连接播放源" : media.sourceName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Circle()
                .fill(media.isPlaying ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }

    // MARK: - Media row

    private var mediaRow: some View {
        HStack(spacing: 14) {
            ArtworkView(data: media.artworkData, size: 76)

            VStack(alignment: .leading, spacing: 4) {
                Text(media.isEmpty ? "未在播放" : media.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)

                Text(media.artist)
                    .font(.system(size: 13))
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
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { seekPosition ?? media.estimatedCurrentPosition },
                    set: { seekPosition = $0 }
                ),
                in: 0...max(media.duration, 1),
                onEditingChanged: { editing in
                    guard !editing, let position = seekPosition else { return }
                    controller.seek(to: position)
                    seekPosition = nil
                    resync(after: 0.5)
                }
            )
            .controlSize(.mini)
            .disabled(!media.capabilities.contains(.canSeek))

            HStack {
                Text(MediaInfo.formatTime(seekPosition ?? media.estimatedCurrentPosition))
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

    private var controls: some View {
        HStack(spacing: 30) {
            Spacer()

            iconButton("backward.fill", size: 20, enabled: media.capabilities.canSkipPrevious) {
                controller.previousTrack()
                resync(after: 0.5)
            }

            Button {
                controller.togglePlayPause()
                resync(after: 0.3)
            } label: {
                Image(systemName: media.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .disabled(!media.capabilities.canTogglePlayPause)

            iconButton("forward.fill", size: 20, enabled: media.capabilities.canSkipNext) {
                controller.nextTrack()
                resync(after: 0.5)
            }

            Spacer()
        }
    }

    private func iconButton(
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
                syncSystemAudio()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : volumeIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(isMuted ? "取消静音" : "静音")

            Slider(
                value: Binding(
                    get: { isMuted ? 0 : volumeLevel },
                    set: { newValue in
                        volumeLevel = newValue
                        isMuted = false
                        controller.setSystemVolume(Int(newValue))
                    }
                ),
                in: 0...100
            )
            .controlSize(.mini)

            Text("\(Int(volumeLevel))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var volumeIcon: String {
        switch Int(volumeLevel) {
        case 0:       return "speaker.fill"
        case 1..<33:  return "speaker.wave.1.fill"
        case 33..<66: return "speaker.wave.2.fill"
        default:      return "speaker.wave.3.fill"
        }
    }

    // MARK: - Footer

    private var openAppButton: some View {
        Button {
            controller.activateApp(bundleID: media.sourceID)
        } label: {
            Label("在 \(media.sourceName) 中打开", systemImage: "arrow.up.forward.app")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func resync(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            monitor.refreshNowPlaying()
        }
    }

    private func syncSystemAudio() {
        let c = controller
        volumeLevel = Double(c.getSystemVolume())
        isMuted = c.isMuted()
    }
}
