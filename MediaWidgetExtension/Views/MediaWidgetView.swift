// MediaWidgetView.swift
// MediaWidgetExtension
//
// Widget UI for the small, medium and large families.
//
// Layouts are kept deliberately compact: macOS applies its own content margins
// around a widget, so a medium widget really only has ~332×138 pt to work with.

import SwiftUI
import WidgetKit

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Main Widget View

struct MediaWidgetView: View {
    let entry: MediaWidgetEntry

    /// Explicit family override, used by previews and offscreen rendering.
    /// `nil` means "read it from the widget environment".
    var familyOverride: WidgetFamily?

    @Environment(\.widgetFamily) private var environmentFamily

    private var widgetFamily: WidgetFamily { familyOverride ?? environmentFamily }
    private var media: MediaInfo { entry.mediaInfo }
    private var isEmpty: Bool { media.isEmpty }

    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            compactLayout
        case .systemLarge:
            largeLayout
        default:
            mediumLayout
        }
    }

    // MARK: - Compact (.systemSmall)

    private var compactLayout: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                artworkView(size: 58)

                Button(intent: TogglePlayPauseIntent()) {
                    Image(systemName: media.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 17))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .disabled(!media.capabilities.canTogglePlayPause || isEmpty)
                .offset(x: 3, y: 3)
            }

            VStack(spacing: 1) {
                Text(isEmpty ? "未在播放" : media.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(media.artist)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            progressBar(height: 3)
        }
    }

    // MARK: - Medium (.systemMedium)

    private var mediumLayout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                artworkView(size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isEmpty ? "未在播放" : media.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(isEmpty ? .secondary : .primary)

                    Text(media.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    sourceLabel(fontSize: 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            progressRow(fontSize: 8.5, barHeight: 3)

            controlsRow(iconSize: 13, playSize: 21, spacing: 26)
        }
    }

    // MARK: - Large (.systemLarge)

    private var largeLayout: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                artworkView(size: 128)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isEmpty ? "未在播放" : media.title)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(isEmpty ? .secondary : .primary)

                    Text(media.artist)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let album = media.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    sourceLabel(fontSize: 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            progressRow(fontSize: 9.5, barHeight: 4)

            controlsRow(iconSize: 17, playSize: 32, spacing: 38)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Components

    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
        Group {
            if let data = media.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
    }

    private func sourceLabel(fontSize: CGFloat) -> some View {
        HStack(spacing: 3) {
            let info = media.sourceAppInfo
            Image(systemName: info.symbolName)
                .font(.system(size: fontSize))
            Text(isEmpty ? "未连接" : info.displayName)
                .font(.system(size: fontSize))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }

    /// Progress bar with elapsed / total labels.
    private func progressRow(fontSize: CGFloat, barHeight: CGFloat) -> some View {
        VStack(spacing: 3) {
            progressBar(height: barHeight)

            HStack(spacing: 0) {
                Text(media.formattedCurrentPosition)
                    .monospacedDigit()
                Spacer(minLength: 4)
                Text(media.formattedDuration)
                    .monospacedDigit()
            }
            .font(.system(size: fontSize))
            .foregroundStyle(.secondary)
        }
    }

    private func progressBar(height: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(isEmpty ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.accentColor))
                    .frame(width: max(0, geometry.size.width * media.progress))
            }
        }
        .frame(height: height)
    }

    private func controlsRow(iconSize: CGFloat, playSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Spacer(minLength: 0)

            Button(intent: PreviousTrackIntent()) {
                Image(systemName: "backward.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(media.capabilities.canSkipPrevious && !isEmpty ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .disabled(!media.capabilities.canSkipPrevious || isEmpty)

            Button(intent: TogglePlayPauseIntent()) {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: playSize))
                    .foregroundStyle(media.capabilities.canTogglePlayPause && !isEmpty ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .disabled(!media.capabilities.canTogglePlayPause || isEmpty)

            Button(intent: NextTrackIntent()) {
                Image(systemName: "forward.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(media.capabilities.canSkipNext && !isEmpty ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .disabled(!media.capabilities.canSkipNext || isEmpty)

            Spacer(minLength: 0)
        }
    }
}
