// MenuBarView.swift
// MediaWidget
//
// Menu bar popover showing current media info and controls.

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: MediaMonitor

    private var media: MediaInfo {
        monitor.currentMedia
    }

    var body: some View {
        VStack(spacing: 12) {
            headerSection
            Divider()
            mediaInfoSection
            progressSection
            controlsSection
            volumeSection
            Divider()
            footerSection
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            monitor.startMonitoring()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: media.sourceAppInfo.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(media.isEmpty ? "未连接" : media.sourceName)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Circle()
                .fill(media.isPlaying ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Media Info

    private var mediaInfoSection: some View {
        HStack(spacing: 12) {
            ArtworkView(data: media.artworkData, size: 56)

            VStack(alignment: .leading, spacing: 4) {
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
        HStack(spacing: 24) {
            Spacer()
            Button {
                controller.previousTrack()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    monitor.refreshNowPlaying()
                }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)

            Button {
                controller.togglePlayPause()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    monitor.refreshNowPlaying()
                }
            } label: {
                Image(systemName: media.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)

            Button {
                controller.nextTrack()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    monitor.refreshNowPlaying()
                }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Volume

    private var volumeSection: some View {
        HStack(spacing: 8) {
            let vol = controller.getSystemVolume()
            let muted = controller.isMuted()

            Button {
                controller.toggleMute()
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : volumeIcon(for: vol))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            Text("\(muted ? 0 : vol)%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            Spacer()

            Button {
                controller.setSystemVolume(max(0, controller.getSystemVolume() - 10))
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                controller.setSystemVolume(min(100, controller.getSystemVolume() + 10))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
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

            Spacer()

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
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

    private var controller: MediaController {
        MediaController(bridge: monitor.bridge)
    }

    private func volumeIcon(for vol: Int) -> String {
        switch vol {
        case 0:     return "speaker.slash.fill"
        case 1..<33: return "speaker.wave.1.fill"
        case 33..<66: return "speaker.wave.2.fill"
        default:    return "speaker.wave.3.fill"
        }
    }
}

// MARK: - Artwork View

struct ArtworkView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data = data, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.6),
                        Color.accentColor.opacity(0.3),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15, style: .continuous))
    }
}
