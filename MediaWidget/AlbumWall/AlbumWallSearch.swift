import SwiftUI

struct AlbumWallSearch: View {
    let albums: [WallAlbum]
    let artwork: (WallAlbum) -> AlbumArtwork.Request?
    let locate: (WallAlbum) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchHasFocus: Bool
    @State private var text = ""
    @State private var selection: String?

    private var results: [WallAlbum] { AlbumWallSearchResults.matching(albums, query: text) }
    private var selectedAlbum: WallAlbum? { results.first { $0.id == selection } ?? results.first }

    var body: some View {
        let matches = results
        let highlighted = matches.first { $0.id == selection } ?? matches.first
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("搜索专辑或艺人", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchHasFocus)
                    .onSubmit { if let album = selectedAlbum { locate(album) } }
                    .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
            }

            if matches.isEmpty {
                ContentUnavailableView(albums.isEmpty ? "唱片墙暂无专辑" : "没有匹配的唱片", systemImage: "magnifyingglass")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(matches) { album in
                                row(album, selected: album.id == highlighted?.id).id(album.id)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .onChange(of: selection) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("定位") {
                    if let album = selectedAlbum { locate(album) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedAlbum == nil)
            }
        }
        .padding(20)
        .frame(width: 470, height: 420)
        .onAppear {
            searchHasFocus = true
            selection = results.first?.id
        }
        .onChange(of: text) { selection = results.first?.id }
    }

    private func row(_ album: WallAlbum, selected: Bool) -> some View {
        Button {
            locate(album)
        } label: {
            HStack(spacing: 10) {
                AlbumWallArtwork(request: artwork(album)) { image in
                    ZStack {
                        RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.07))
                        if let image {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(.rect(cornerRadius: 4))
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text([album.artist, album.sourceName].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(selected ? 0.16 : 0),
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func moveSelection(by offset: Int) {
        let visible = results
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selection } ?? 0
        selection = visible[min(visible.count - 1, max(0, current + offset))].id
    }
}

enum AlbumWallSearchResults {
    static func matching(_ albums: [WallAlbum], query: String) -> [WallAlbum] {
        let words = normalized(query).split(whereSeparator: \.isWhitespace)
        var seen = Set<String>()
        return albums.filter { album in
            guard seen.insert(album.id).inserted else { return false }
            guard !words.isEmpty else { return true }
            let text = normalized([album.title, album.artist].compactMap { $0 }.joined(separator: " "))
            return words.allSatisfy { text.contains($0) }
        }
    }

    private static func normalized(_ value: String) -> String {
        let simplified = value.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? value
        return simplified.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
