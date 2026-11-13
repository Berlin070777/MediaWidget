// FloatingPanelView.swift
// MediaWidget
//
// A standalone floating panel view with full media controls including
// draggable progress bar, volume slider, and source switching.

import SwiftUI

struct FloatingPanelView: View {
    @StateObject private var monitor = MediaMonitor()
    @State private var seekPosition: Double? = nil
    @State private var volumeLevel: Double = 50

    private var media: MediaInfo {
        monitor.currentMedia
    }

    private var controller: MediaController {
        MediaController(bridge: monitor.bridge)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: media.sourceAppInfo.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(media.isEmpty ? "未连接" : media.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(media.isPlaying ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
            }

            // Media Info
            HStack(spacing: 14) {
                ArtworkView(data: media.artworkData, size: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title)
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

            // Progress with draggable slider
            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { seekPosition ?? media.estimatedCurrentPosition },
                        set: { newValue in seekPosition = newValue }
                    ),
                    in: 0...max(media.duration, 1),
                    onEditingChanged: { editing in
                        if !editing, let pos = seekPosition {
                            controller.seek(to: pos)
                            seekPosition = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                monitor.refreshNowPlaying()
                            }
                        }
                    }
                )
                .disabled(media.isEmpty || !media.capabilities.contains(.canSeek))

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

            // Controls
            HStack(spacing: 28) {
                Spacer()

                Button {
                    controller.previousTrack()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        monitor.refreshNowPlaying()
                    }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)

                Button {
                    controller.togglePlayPause()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        monitor.refreshNowPlaying()
                    }
                } label: {
                    Image(systemName: media.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38))
                }
                .buttonStyle(.plain)

                Button {
                    controller.nextTrack()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        monitor.refreshNowPlaying()
                    }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)

                Spacer()
            }

            // Volume slider
            HStack(spacing: 8) {
                Button {
                    controller.toggleMute()
                    volumeLevel = Double(controller.getSystemVolume())
                } label: {
                    Image(systemName: controller.isMuted() ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                }
                .buttonStyle(.plain)

                Slider(value: $volumeLevel, in: 0...100) { editing in
                    if !editing {
                        controller.setSystemVolume(Int(volumeLevel))
                    }
                }
                .onChange(of: volumeLevel) { _, newValue in
                    controller.setSystemVolume(Int(newValue))
                }

                Text("\(Int(volumeLevel))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            // Open in app
            if !media.isEmpty {
                Button {
                    controller.activateApp(bundleID: media.sourceID)
                } label: {
                    Label("在 \(media.sourceName) 中打开", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            monitor.startMonitoring()
            volumeLevel = Double(controller.getSystemVolume())
        }
    }
}
