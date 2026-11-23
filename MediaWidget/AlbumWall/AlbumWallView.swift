import SwiftUI

enum AlbumWallLayout: String, CaseIterable {
    static let preference = "albumWallLayout"
    case carousel, grid

    var title: String { self == .carousel ? "立体翻阅" : "封面网格" }
}

enum AlbumWallCollection: String, CaseIterable {
    static let preference = "albumWallCollection"
    case recent = "最近播放"
    case favorites = "我的收藏"
}

struct AlbumWallFocus: Equatable {
    let albumID: String
    private let revision = UUID()
}

struct AlbumWallView: View {
    @ObservedObject var monitor: MediaMonitor
    let library: AlbumWallStore
    let input: AlbumWallInput
    @Bindable var navigation: MediaWindowNavigation

    @AppStorage("downloadArtwork") private var downloadArtwork = true
    @AppStorage(AlbumWallStore.historyPreference) private var recordHistory = true
    @AppStorage(AlbumWallLayout.preference) private var layout: AlbumWallLayout = .carousel
    @AppStorage(AlbumWallCollection.preference) private var collection: AlbumWallCollection = .recent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focus: AlbumWallFocus?
    @State private var selectedAlbum: WallAlbum?
    @State private var playbackError: String?
    @State private var editingBackArtwork: WallAlbum?

    private var currentMedia: MediaInfo { monitor.currentMedia }
    private var currentAlbum: WallAlbum? { WallAlbum(media: currentMedia) }
    private var albums: [WallAlbum] {
        collection == .recent ? library.recentAlbums : library.favorites
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = library.errorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if albums.isEmpty {
                emptyCollection
            } else {
                GeometryReader { proxy in
                    switch layout {
                    case .carousel:
                        AlbumWallCarousel(albums: albums, size: proxy.size, input: input, focus: focus,
                                          showDetails: { selectedAlbum = $0 }) {
                            album, size, turn, reflection, centered, open in
                            tile(album, size: size, turn: turn, reflection: reflection, centered: centered, open: open)
                        }
                        .id(collection)
                    case .grid:
                        wall(size: proxy.size)
                    }
                }
            }

            if !currentMedia.isEmpty {
                playbackBar(for: currentMedia)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .onChange(of: navigation.albumFocus, initial: true) { _, request in
            guard let request else { return }
            navigation.albumFocus = nil
            reveal(request)
        }
        .sheet(isPresented: $navigation.isSearchingAlbums) {
            AlbumWallSearch(albums: library.recentAlbums + library.favorites, artwork: artwork(for:)) { album in
                navigation.isSearchingAlbums = false
                reveal(AlbumWallFocus(albumID: album.id))
            }
        }
        .sheet(item: $selectedAlbum) { selected in
            let album = library.albums.first(where: { $0.id == selected.id }) ?? selected
            AlbumWallDetails(album: album, artwork: artwork(for: album), monitor: monitor,
                             removeRecent: recentRemoval(for: album)) { catalog in
                if let id = catalog.albumID { library.rememberNeteaseAlbumID(id, for: album.id) }
            } toggleFavorite: {
                library.toggleFavorite(album)
                if !library.albums.contains(where: { $0.id == album.id }) {
                    selectedAlbum = nil
                }
            }
        }
        .sheet(item: $editingBackArtwork) { album in
            AlbumBackArtworkSheet(album: album, library: library)
        }
        .alert("无法确认播放", isPresented: Binding(
            get: { playbackError != nil }, set: { if !$0 { playbackError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
    }

    private func reveal(_ request: AlbumWallFocus) {
        if !albums.contains(where: { $0.id == request.albumID }) {
            guard let album = library.albums.first(where: { $0.id == request.albumID }) else { return }
            collection = album.lastPlayedAt == nil ? .favorites : .recent
        }
        focus = request
    }

    private func playbackBar(for media: MediaInfo) -> some View {
        HStack(spacing: 14) {
            PlaybackTransportControls(media: media, compact: true, submit: { monitor.submit($0, for: media) })
            Divider().frame(height: 16)
            PlaybackProgress(media: media, compact: true, seek: { monitor.seek($0, for: media) })
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .frame(height: 42)
        .mediaGlass(in: Capsule())
        .frame(maxWidth: 580)
        .padding(.horizontal, 28)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private func wall(size: CGSize) -> some View {
        let gap: CGFloat = 15
        let usableWidth = max(0, min(size.width - 52, 1320))
        let capacity = max(2, min(7, Int((usableWidth + gap) / 172)))
        let columns = max(1, min(albums.count, capacity))
        let sparse = albums.count < 3
        let maximum: CGFloat = albums.count == 1 ? 312 : albums.count == 2 ? 270 : 220
        let availablePerCover = (usableWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let heightLimit = sparse ? max(1, size.height - 40) : maximum
        let artworkSize = max(1, min(availablePerCover, maximum, heightLimit))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(artworkSize), spacing: gap), count: columns),
                          spacing: gap) {
                    ForEach(albums) { album in
                        tile(album, size: artworkSize) { selectedAlbum = album }
                            .overlay {
                                if focus?.albumID == album.id {
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(.white.opacity(0.82), lineWidth: 2)
                                        .allowsHitTesting(false)
                                }
                            }
                            .accessibilityAddTraits(focus?.albumID == album.id ? .isSelected : [])
                            .id(album.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, sparse ? 18 : 11)
                .padding(.bottom, sparse ? 22 : 24)
                .frame(maxWidth: .infinity, minHeight: sparse ? size.height : 0)
            }
            .task(id: focus) {
                guard let focus else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                    proxy.scrollTo(focus.albumID, anchor: .center)
                }
            }
        }
        .id(collection)
    }

    private func tile(_ album: WallAlbum, size: CGFloat, turn: Double = 0, reflection: CGFloat = 0,
                      centered: Bool = false, open: @escaping () -> Void) -> some View {
        let playAlbum: (() -> Void)? = album.neteaseAlbumID.map { albumID in
            {
                Task {
                    playbackError = await monitor.playNetease(.album(albumID))
                }
            }
        }
        return AlbumWallArtwork(request: artwork(for: album)) { image in
            let front = AlbumWallTile(album: album, image: image, quiet: reflection > 0,
                                      isPlaying: currentMedia.isPlaying && currentAlbum?.id == album.id,
                                      size: size, showDetails: open, playAlbum: playAlbum,
                                      canStartPlayback: !monitor.requestingAlbumPlayback, removeRecent: recentRemoval(for: album),
                                      editBackArtwork: { editingBackArtwork = album }) {
                library.toggleFavorite(album)
            }
            if reflection > 0 {
                let backRequest = centered && monitor.showArtwork ? library.backArtwork(for: album) : nil
                let lookup = centered && abs(turn) == 1 && backRequest == nil && downloadArtwork && monitor.showArtwork
                let status: AlbumBackArtworkStatus = if !monitor.showArtwork {
                    .artworkHidden
                } else if !downloadArtwork {
                    .downloadsOff
                } else {
                    library.backLookupStatus(for: album)
                }
                AlbumWallArtwork(request: backRequest) { backImage in
                    AlbumSleeve(album: album, artwork: image, backArtwork: backImage, backStatus: status, side: size,
                                reflectionHeight: reflection, progress: turn, showDetails: { selectedAlbum = album },
                                editBackArtwork: { editingBackArtwork = album },
                                retryBackLookup: downloadArtwork && monitor.showArtwork ? {
                                    library.startBackLookup(for: album, retry: true)
                                } : nil) {
                        front
                    }
                }
                .task(id: lookup) {
                    guard lookup else { return }
                    try? await Task.sleep(for: .milliseconds(160))
                    if !Task.isCancelled { library.startBackLookup(for: album) }
                }
            } else {
                front
            }
        }
    }

    private func recentRemoval(for album: WallAlbum) -> (() -> Void)? {
        guard collection == .recent, album.lastPlayedAt != nil else { return nil }
        return {
            library.removeFromRecents(album.id)
            if selectedAlbum?.id == album.id { selectedAlbum = nil }
        }
    }

    private func artwork(for album: WallAlbum) -> AlbumArtwork.Request? {
        monitor.showArtwork ? library.artwork(for: album) : nil
    }

    private var emptyCollection: some View {
        ContentUnavailableView(collection == .recent ? "暂无最近播放" : "暂无收藏专辑",
                               systemImage: collection == .recent ? "square.stack" : "heart",
                               description: Text(emptyDescription))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDescription: String {
        if collection == .favorites {
            return "打开专辑详情，或从封面菜单收藏专辑。"
        }
        return recordHistory ? "播放一首能识别专辑的歌曲，封面会出现在这里。" : "可在屏幕左上方的「唱片墙」菜单开启播放记录。"
    }
}

private struct AlbumWallTile: View {
    let album: WallAlbum
    let image: NSImage?
    let quiet: Bool
    let isPlaying: Bool
    let size: CGFloat
    let showDetails: () -> Void
    let playAlbum: (() -> Void)?
    let canStartPlayback: Bool
    let removeRecent: (() -> Void)?
    let editBackArtwork: () -> Void
    let toggleFavorite: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        Button(action: showDetails) {
            WallCover(image: image, size: size, radius: 5)
                .accessibilityHidden(true)
                .overlay(alignment: .bottomLeading) {
                    if (!quiet && hovered) || image == nil {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title).font(.callout.weight(.semibold)).lineLimit(1)
                            if let artist = album.artist {
                                Text(artist).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.white)
                        .padding(10)
                        .padding(.top, 9)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.83)],
                                                   startPoint: .top, endPoint: .bottom))
                        .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if !quiet && isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.7), in: Circle())
                            .padding(7)
                            .accessibilityHidden(true)
                    }
                }
                .clipShape(.rect(cornerRadius: 5))
                .contentShape(Rectangle())
                .shadow(color: .black.opacity(hovered ? 0.31 : 0.16),
                        radius: hovered ? 10 : 4, y: 4)
                .scaleEffect(!quiet && hovered && !reduceMotion ? 1.025 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(album.title)
        .accessibilityValue([album.artist, isPlaying ? "播放中" : nil, album.isFavorite ? "已收藏" : nil]
            .compactMap { $0 }.joined(separator: "，"))
        .accessibilityHint("查看专辑详情")
        .accessibilityActions {
            Button(album.isFavorite ? "取消收藏" : "收藏专辑", action: toggleFavorite)
            if let removeRecent { Button("从最近播放移除", action: removeRecent) }
        }
        .overlay(alignment: .topTrailing) {
            if !quiet && hovered, let playAlbum {
                Button(action: playAlbum) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.72), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canStartPlayback)
                .padding(8)
                .accessibilityLabel("播放专辑「\(album.title)」")
                .help("播放专辑")
            }
        }
        .zIndex(hovered ? 1 : 0)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
        .contextMenu {
            Button("添加或更换背封…", action: editBackArtwork)
            if let playAlbum {
                Button("播放专辑", systemImage: "play.fill", action: playAlbum)
                    .disabled(!canStartPlayback)
                Divider()
            }
            Button(album.isFavorite ? "取消收藏" : "收藏专辑", action: toggleFavorite)
            if let removeRecent {
                Divider()
                Button("从最近播放移除", systemImage: "trash", role: .destructive, action: removeRecent)
            }
        }
    }
}

private struct AlbumWallDetails: View {
    let album: WallAlbum
    let artwork: AlbumArtwork.Request?
    @ObservedObject var monitor: MediaMonitor
    let removeRecent: (() -> Void)?
    let catalogLoaded: (AlbumWallCatalog) -> Void
    let toggleFavorite: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var catalog: AlbumWallCatalog?
    @State private var playbackError: String?

    private var albumID: String? { catalog?.albumID ?? album.neteaseAlbumID }
    private var playingID: String? {
        monitor.allSources.first { $0.bundleID == Constants.KnownApp.neteaseMusic && $0.isPlaying }?.itemID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                AlbumWallArtwork(request: artwork) { image in
                    WallCover(image: image, size: 122, radius: 6)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(album.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(3)
                        .accessibilityAddTraits(.isHeader)
                    if let artist = album.artist {
                        Text(artist).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text(album.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if let albumID {
                            Button("播放专辑", systemImage: "play.fill") { start(.album(albumID)) }
                                .mediaGlassButton(prominent: true)
                                .disabled(monitor.requestingAlbumPlayback)
                        }
                        FavoriteAlbumButton(isFavorite: album.isFavorite, albumTitle: album.title, action: toggleFavorite)
                    }
                    .padding(.top, 5)
                }
                Spacer(minLength: 0)
            }

            if album.isNetease {
                Divider()
                tracks
            }

            HStack {
                if monitor.requestingAlbumPlayback {
                    ProgressView().controlSize(.small)
                    Text("正在等待网易云确认").font(.caption).foregroundStyle(.secondary)
                } else if let playbackError {
                    Text(playbackError).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let removeRecent {
                    Button("从最近播放移除", systemImage: "trash", role: .destructive, action: removeRecent)
                        .buttonStyle(.borderless)
                }
                Button("完成") { dismiss() }
                    .mediaGlassButton()
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(width: 450, alignment: .leading)
        .padding(24)
        .task(id: album.id) {
            guard album.isNetease else { return }
            let result = await monitor.albumCatalog(for: album)
            guard !Task.isCancelled else { return }
            catalog = result
            catalogLoaded(result)
        }
    }

    @ViewBuilder
    private var tracks: some View {
        Text("已播放曲目").font(.headline)
        if let catalog {
            if catalog.tracks.isEmpty {
                Text("本机没有这张专辑的选曲记录。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(catalog.tracks) { track in
                            Button {
                                start(.song(track.id))
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: playingID == track.id ? "waveform" : "play")
                                        .frame(width: 18)
                                        .foregroundStyle(playingID == track.id ? Color.accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title).lineLimit(1)
                                        if let artist = track.artist {
                                            Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if let duration = track.duration {
                                        Text(MediaInfo.formatTime(duration))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 38)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(monitor.requestingAlbumPlayback)
                            .accessibilityLabel("播放「\(track.title)」")
                            .accessibilityValue(playingID == track.id ? "播放中" : "")
                        }
                    }
                }
                .frame(height: min(180, CGFloat(catalog.tracks.count) * 41))
            }
        } else {
            ProgressView().controlSize(.small)
                .accessibilityLabel("正在读取已播放曲目")
        }
    }

    private func start(_ target: NeteaseAlbumPlayback.Target) {
        playbackError = nil
        Task { playbackError = await monitor.playNetease(target) }
    }
}

struct AlbumWallArtwork<Content: View>: View {
    let request: AlbumArtwork.Request?
    @ViewBuilder let content: (NSImage?) -> Content
    @State private var loaded: (request: AlbumArtwork.Request, image: NSImage)?

    var body: some View {
        content(loaded?.request == request ? loaded?.image : nil)
            .task(id: request) {
                guard let request else {
                    loaded = nil
                    return
                }
                let image = await AlbumArtwork.shared.thumbnail(request)
                guard !Task.isCancelled else { return }
                loaded = image.map { (request, NSImage(cgImage: $0, size: .zero)) }
            }
    }
}

private struct WallCover: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Color.primary.opacity(0.08)
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: size, height: size)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.22, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(.rect(cornerRadius: radius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(image == nil ? "封面不可用" : "媒体封面")
    }
}

private struct FavoriteAlbumButton: View {
    let isFavorite: Bool
    let albumTitle: String
    let action: () -> Void

    private var label: String { isFavorite ? "取消收藏" : "收藏专辑" }

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isFavorite ? Color(red: 0.80, green: 0.32, blue: 0.30) : .secondary)
                .frame(width: 31, height: 31)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel("\(label)「\(albumTitle)」")
    }
}
