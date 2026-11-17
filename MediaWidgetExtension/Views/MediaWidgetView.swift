import SwiftUI
import WidgetKit

struct MediaWidgetView: View {
    let entry: MediaWidgetEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    private var media: MediaInfo { entry.mediaInfo }
    private var compact: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }
    private var palette: ArtworkPalette? {
        renderingMode == .fullColor && entry.showArtwork ? ArtworkPalette.from(media.artworkData) : nil
    }
    private var accent: Color { palette?.accent ?? .accentColor }

    var body: some View {
        Group {
            if media.isEmpty {
                emptyState
            } else if compact {
                smallLayout
            } else if large {
                largeLayout
            } else {
                mediumLayout
            }
        }
        .tint(accent)
        .background { ambientWash }
        .widgetURL(media.isEmpty ? Constants.sourcePickerURL : nil)
    }

    private var ambientWash: some View {
        Group {
            if let palette {
                RadialGradient(colors: [palette.top.opacity(0.18), palette.bottom.opacity(0.07), .clear],
                               center: .center, startRadius: 4, endRadius: compact ? 76 : 160)
                    .mask { RoundedRectangle(cornerRadius: 22).blur(radius: 10) }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Layouts

    private var smallLayout: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                sourceChip
                Spacer(minLength: 0)
                if media.capabilities.contains(.canSeek) { seekPanelButton }
            }
            VStack(spacing: 4) {
                if entry.showArtwork {
                    artworkView(corner: 11).frame(width: 48, height: 48)
                }
                mediaLink {
                    Text(media.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .frame(maxHeight: .infinity)
            progressIndicator
            controlsRow(diameter: 27, playDiameter: 31, iconSize: 10, playIconSize: 13, spacing: 10)
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 13) {
            if entry.showArtwork {
                artworkView(corner: 14).frame(width: 102, height: 102)
            }
            VStack(alignment: .leading, spacing: 5) {
                sourceChip
                mediaLink {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(media.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(media.artist ?? "作者不可用")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
                progress
                controlsRow(diameter: 28, playDiameter: 32, iconSize: 11, playIconSize: 14, spacing: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var largeLayout: some View {
        VStack(spacing: 10) {
            HStack {
                sourceChip
                Spacer(minLength: 8)
                volumeLabel
            }
            if entry.showArtwork {
                artworkView(corner: 16)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: .infinity)
            }
            mediaLink {
                VStack(spacing: 3) {
                    Text(media.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(media.artist ?? "作者不可用")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            progress
            controlsRow(diameter: 38, playDiameter: 46, iconSize: 15, playIconSize: 19, spacing: 18)
        }
    }

    private var emptyState: some View {
        VStack(spacing: compact ? 7 : 11) {
            Spacer(minLength: 0)
            Image(systemName: "waveform")
                .font(.system(size: compact ? 20 : 28, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 50 : 66, height: compact ? 50 : 66)
                .widgetControlSurface(in: Circle())
            Text("未检测到媒体")
                .font(.system(size: compact ? 13 : 16, weight: .semibold))
            Text("开始播放后即可选择来源")
                .font(.system(size: compact ? 9 : 11))
                .foregroundStyle(.secondary)
            if !compact {
                Text("查看播放源")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .widgetControlSurface(in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Source switcher

    private var sourceChip: some View {
        let name = WidgetSourceStyle.shortName(media.sourceName)
        let automatic = entry.preferredSource.isEmpty
        return Link(destination: Constants.sourcePickerURL) {
            HStack(spacing: 5) {
                Image(systemName: media.sourceSymbol)
                    .font(.system(size: compact ? 8 : 9, weight: .semibold))
                Text(automatic && !compact ? "自动 · \(name)" : name)
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                    .lineLimit(1)
                if !compact && media.isPlaying {
                    Circle().fill(.green).frame(width: 5, height: 5)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: compact ? 7 : 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, compact ? 7 : 9)
            .frame(minHeight: 22)
            .contentShape(Capsule())
            .widgetControlSurface(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择播放源，当前为\(automatic ? "自动 · " : "")\(name)")
        .accessibilityHint("打开可用播放源列表")
    }

    // MARK: - Metadata

    private func mediaLink<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button(intent: WidgetPlaybackIntent(.activate, media: media)) {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开来源应用")
    }

    private var volumeLabel: some View {
        Label(media.volume.map { "媒体音量 \(Int(($0 * 100).rounded()))%" } ?? "媒体音量不可用",
              systemImage: "speaker.wave.2.fill")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var progressInterval: ClosedRange<Date>? {
        // ImageRenderer previews use the same layout with a static sample.
        guard familyOverride == nil, media.isPlaying, let position = media.position(at: entry.date),
              let duration = media.duration, duration.isFinite, duration > 0,
              media.playbackRate.isFinite, (0.05...16).contains(media.playbackRate) else { return nil }
        let start = entry.date.addingTimeInterval(-position / media.playbackRate)
        return start...start.addingTimeInterval(duration / media.playbackRate)
    }

    private var seekPanelButton: some View {
        Button(intent: WidgetPlaybackIntent(.openPanel, media: media)) {
            Label("调整进度", systemImage: "slider.horizontal.3")
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .labelStyle(SeekButtonLabelStyle(iconOnly: compact))
                .fixedSize()
                .padding(.horizontal, compact ? 5 : 7)
                .frame(minHeight: 22)
                .contentShape(Capsule())
                .widgetControlSurface(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开面板调整进度")
        .accessibilityHint("在悬浮面板拖动进度")
    }

    @ViewBuilder
    private var progressIndicator: some View {
        if let position = media.position(at: entry.date), let duration = media.duration,
           duration.isFinite, duration > 0 {
            Group {
                if familyOverride != nil {
                    // Offscreen previews cannot snapshot the native AppKit progress view.
                    GeometryReader { geometry in
                        Capsule()
                            .fill(.quaternary)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(accent)
                                    .frame(width: geometry.size.width * min(max(position / duration, 0), 1))
                            }
                    }
                    .frame(height: 4)
                } else if let interval = progressInterval {
                    ProgressView(timerInterval: interval, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                } else {
                    ProgressView(value: position, total: duration)
                }
            }
            .progressViewStyle(.linear)
            .tint(accent)
            .accessibilityLabel("播放进度")
        }
    }

    private var progress: some View {
        VStack(spacing: 3) {
            progressIndicator
            HStack(spacing: 4) {
                if let interval = progressInterval, abs(media.playbackRate - 1) < 0.001 {
                    Text(timerInterval: interval, countsDown: false, showsHours: (media.duration ?? 0) >= 3_600)
                } else {
                    Text(MediaInfo.formatTime(media.position(at: entry.date)))
                }
                Text("/").foregroundStyle(.tertiary)
                Text(MediaInfo.formatTime(media.duration))
                Spacer(minLength: 0)
                if media.capabilities.contains(.canSeek) { seekPanelButton }
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

    private func controlsRow(diameter: CGFloat, playDiameter: CGFloat,
                             iconSize: CGFloat, playIconSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            if !compact || media.capabilities.contains(.canPreviousTrack) {
                control(.previous, title: "上一项", icon: "backward.fill",
                        diameter: diameter, iconSize: iconSize)
            }
            control(media.isPlaying ? .pause : .play, title: media.isPlaying ? "暂停" : "播放",
                    icon: media.isPlaying ? "pause.fill" : "play.fill",
                    diameter: playDiameter, iconSize: playIconSize, prominent: true)
            if !compact || media.capabilities.contains(.canNextTrack) {
                control(.next, title: "下一项", icon: "forward.fill",
                        diameter: diameter, iconSize: iconSize)
            }
        }
    }

    private func control(_ action: WidgetPlaybackAction, title: String, icon: String,
                         diameter: CGFloat, iconSize: CGFloat, prominent: Bool = false) -> some View {
        let enabled = MediaCommand(rawValue: action.rawValue)
            .map { media.capabilities.contains($0.capability) } ?? false
        return Button(intent: WidgetPlaybackIntent(action, media: media)) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .widgetControlSurface(in: Circle(), tint: prominent ? accent : nil)
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .invalidatableContent()
        .disabled(!enabled)
    }

    // MARK: - Artwork

    private func artworkView(corner: CGFloat) -> some View {
        Group {
            if let data = media.artworkData, let image = NSImage(data: data) {
                let artwork = Image(nsImage: image).resizable()
                if #available(macOS 26, *) {
                    artwork.widgetAccentedRenderingMode(.fullColor).scaledToFill()
                } else {
                    artwork.scaledToFill()
                }
            } else {
                GeometryReader { geometry in
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "music.note")
                            .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.34))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: corner))
        .overlay {
            RoundedRectangle(cornerRadius: corner).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 5, y: 2)
        .accessibilityLabel(media.artworkData == nil ? "封面不可用" : "封面")
    }
}

private struct SeekButtonLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            if !iconOnly { configuration.title }
        }
        .foregroundStyle(.primary)
    }
}
