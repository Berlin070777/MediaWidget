// MediaWidgetView.swift
// MediaWidgetExtension
//
// Widget UI for medium and large widget families.

import SwiftUI
import WidgetKit

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Main Widget View

struct MediaWidgetView: View {
    let entry: MediaWidgetEntry

    @Environment(\.widgetFamily) var widgetFamily

    private var mediaInfo: MediaInfo { entry.mediaInfo }
    private var isEmpty: Bool { mediaInfo.sourceID.isEmpty }

    var body: some View {
        Group {
            switch widgetFamily {
            case .systemMedium:
                mediumLayout
            case .systemLarge:
                largeLayout
            default:
                mediumLayout
            }
        }
    }

    // MARK: - Medium Layout

    private var mediumLayout: some View {
        VStack(spacing: 8) {
            // Top row: artwork + track info
            HStack(spacing: 12) {
                artworkView(size: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mediaInfo.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .foregroundStyle(isEmpty ? .secondary : .primary)

                    Text(mediaInfo.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    sourceLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Progress bar
            progressSection

            // Control buttons
            controlButtons
        }
        .padding(.vertical, 4)
    }

    // MARK: - Large Layout

    private var largeLayout: some View {
        VStack(spacing: 12) {
            // Source badge at the top
            HStack {
                sourceLabel
                Spacer()
                if let volume = mediaInfo.volume {
                    volumeLabel(volume: volume)
                }
            }

            // Artwork + track info
            HStack(spacing: 16) {
                artworkView(size: 90)

                VStack(alignment: .leading, spacing: 6) {
                    Text(mediaInfo.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .foregroundStyle(isEmpty ? .secondary : .primary)

                    Text(mediaInfo.artist)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let album = mediaInfo.album, !album.isEmpty {
                        Text(album)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 4)

            // Progress bar
            progressSection

            // Control buttons (larger in large widget)
            controlButtons
        }
        .padding(.vertical, 4)
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
        Group {
            if let artworkData = mediaInfo.artworkData,
               let nsImage = NSImage(data: artworkData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Source Label

    private var sourceLabel: some View {
        HStack(spacing: 4) {
            let info = mediaInfo.sourceAppInfo
            Image(systemName: info.symbolName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(isEmpty ? "未连接" : info.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Volume Label

    private func volumeLabel(volume: Float) -> some View {
        HStack(spacing: 4) {
            Image(systemName: volumeIconName(for: volume))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(volume * 100))%")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func volumeIconName(for volume: Float) -> String {
        switch volume {
        case 0:
            return "speaker.slash.fill"
        case ..<0.33:
            return "speaker.wave.1.fill"
        case ..<0.66:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 4)

                    Capsule()
                        .fill(isEmpty ? Color.secondary : Color.accentColor)
                        .frame(
                            width: max(0, geometry.size.width * mediaInfo.progress),
                            height: 4
                        )
                }
            }
            .frame(height: 4)

            HStack {
                Text(mediaInfo.formattedCurrentPosition)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                Text(mediaInfo.formattedDuration)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: widgetFamily == .systemLarge ? 32 : 24) {
            Spacer()

            // Previous Track
            Button(intent: PreviousTrackIntent()) {
                Image(systemName: "backward.fill")
                    .font(.system(size: controlIconSize))
                    .foregroundStyle(
                        mediaInfo.capabilities.contains(.canPreviousTrack) && !isEmpty
                            ? .primary : .tertiary
                    )
            }
            .buttonStyle(.plain)
            .disabled(!mediaInfo.capabilities.contains(.canPreviousTrack) || isEmpty)

            // Play / Pause
            Button(intent: TogglePlayPauseIntent()) {
                Image(systemName: mediaInfo.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: controlIconSize * 1.3))
                    .foregroundStyle(
                        (mediaInfo.capabilities.contains(.canPlay) || mediaInfo.capabilities.contains(.canPause)) && !isEmpty
                            ? .primary : .tertiary
                    )
            }
            .buttonStyle(.plain)
            .disabled(
                !(mediaInfo.capabilities.contains(.canPlay) || mediaInfo.capabilities.contains(.canPause)) || isEmpty
            )

            // Next Track
            Button(intent: NextTrackIntent()) {
                Image(systemName: "forward.fill")
                    .font(.system(size: controlIconSize))
                    .foregroundStyle(
                        mediaInfo.capabilities.contains(.canNextTrack) && !isEmpty
                            ? .primary : .tertiary
                    )
            }
            .buttonStyle(.plain)
            .disabled(!mediaInfo.capabilities.contains(.canNextTrack) || isEmpty)

            Spacer()
        }
    }

    private var controlIconSize: CGFloat {
        widgetFamily == .systemLarge ? 18 : 15
    }
}

// MARK: - Preview

#Preview("Medium - Playing", as: .systemMedium) {
    MediaWidget()
} timeline: {
    MediaWidgetEntry(
        date: .now,
        mediaInfo: MediaInfo(
            sourceID: "com.apple.Music",
            sourceName: "Apple Music",
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            artworkData: nil,
            duration: 354,
            currentPosition: 120,
            playbackRate: 1,
            volume: 0.7,
            capabilities: .all,
            lastUpdated: .now,
            positionTimestamp: .now
        )
    )
}

#Preview("Medium - Empty", as: .systemMedium) {
    MediaWidget()
} timeline: {
    MediaWidgetEntry(date: .now, mediaInfo: .empty)
}
