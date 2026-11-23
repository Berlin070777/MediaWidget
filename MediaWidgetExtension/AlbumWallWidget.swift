import AppKit
import SwiftUI
import WidgetKit

struct AlbumWallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Constants.albumWallWidgetKind, provider: AlbumPreviewProvider()) { entry in
            AlbumPreviewView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Constants.albumWallURL)
        }
        .configurationDisplayName("唱片墙")
        .description("看看最近播放或收藏的几张唱片，点按即可打开完整唱片墙。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct AlbumPreviewEntry: TimelineEntry {
    let date: Date
    let albums: [WidgetAlbum]
    var isPlaceholder = false
}

private struct AlbumPreviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlbumPreviewEntry {
        AlbumPreviewEntry(date: .now, albums: [], isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (AlbumPreviewEntry) -> Void) {
        let entry = currentEntry()
        completion(context.isPreview && entry.albums.isEmpty ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlbumPreviewEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> AlbumPreviewEntry {
        AlbumPreviewEntry(date: .now, albums: Array((SharedDefaults.shared.albumPreview() ?? []).prefix(4)))
    }
}

private struct AlbumPreviewView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AlbumPreviewEntry

    private var limit: Int { family == .systemSmall ? 1 : 4 }
    private var albums: [WidgetAlbum] { Array(entry.albums.prefix(limit)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("唱片墙").font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("打开唱片墙")

            if albums.isEmpty && !entry.isPlaceholder {
                VStack(spacing: 7) {
                    Image(systemName: "square.stack").font(.title2)
                    Text("打开唱片墙").font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let count = entry.isPlaceholder ? limit : albums.count
                    let gap: CGFloat = 6
                    let size = max(1, min(proxy.size.height, (proxy.size.width - CGFloat(count - 1) * gap) / CGFloat(count)))
                    HStack(spacing: gap) {
                        if entry.isPlaceholder {
                            ForEach(0..<count, id: \.self) { _ in placeholder.frame(width: size, height: size) }
                        } else {
                            ForEach(albums) { album in
                                Group {
                                    if let image = NSImage(data: album.thumbnail) {
                                        artwork(image)
                                    } else {
                                        placeholder
                                    }
                                }
                                .frame(width: size, height: size)
                                .clipShape(.rect(cornerRadius: 5))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(album.title)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .privacySensitive()
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.16))
            .overlay { Image(systemName: "music.note").foregroundStyle(.tertiary) }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func artwork(_ image: NSImage) -> some View {
        let cover = Image(nsImage: image).resizable()
        if #available(macOS 26, *) {
            cover.widgetAccentedRenderingMode(.fullColor).scaledToFill()
        } else {
            cover.scaledToFill()
        }
    }
}
