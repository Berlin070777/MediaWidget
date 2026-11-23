import SwiftUI
import UniformTypeIdentifiers

struct AlbumBackArtworkSheet: View {
    let album: WallAlbum
    let library: AlbumWallStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var releaseLink = ""
    @State private var isImporting = false
    @State private var loading: Task<Void, Never>?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("唱片背封").font(.headline)
            Text(album.title).foregroundStyle(.secondary).lineLimit(2)
            TextField("MusicBrainz 发行版链接", text: $releaseLink, prompt: Text("粘贴发行版链接"))
                .onSubmit(loadRelease)
            HStack {
                Button("查找发行版本") { openURL(CoverArtArchive.releaseSearch(for: album)) }
                Button("导入本地图片…") { isImporting = true }
                Spacer()
                Button("载入背封", action: loadRelease)
                    .disabled(CoverArtArchive.releaseID(from: releaseLink) == nil)
            }
            .disabled(loading != nil)
            if let error {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
            HStack {
                if loading != nil {
                    ProgressView().controlSize(.small)
                    Text("正在载入背封…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 470)
        .onAppear {
            if let release = album.backReleaseID {
                releaseLink = "https://musicbrainz.org/release/\(release.uuidString.lowercased())"
            }
        }
        .onDisappear { loading?.cancel() }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let file):
                start(release: nil) { await AlbumArtwork.shared.importedBackArtwork(file) }
            case .failure:
                error = "无法打开所选图片。"
            }
        }
    }

    private func loadRelease() {
        guard let release = CoverArtArchive.releaseID(from: releaseLink) else { return }
        start(release: release) {
            let data = try await CoverArtArchive.downloadBack(for: release)
            return await AlbumArtwork.shared.downloadedBackArtwork(data)
        }
    }

    private func start(release: UUID?, _ operation: @escaping () async throws -> Data?) {
        guard loading == nil else { return }
        error = nil
        loading = Task {
            defer { loading = nil }
            do {
                let data = try await operation()
                guard !Task.isCancelled else { return }
                if let data, library.saveBackArtwork(data, releaseID: release, for: album.id) {
                    dismiss()
                } else if data == nil {
                    error = "无法读取背封图片。"
                } else {
                    error = "无法保存背封。"
                }
            } catch CoverArtArchive.Failure.missing {
                error = "这个发行版暂无背封。可尝试其他发行版，或导入本地图片。"
            } catch {
                if !Task.isCancelled { self.error = "背封下载失败，请稍后重试。" }
            }
        }
    }
}

enum CoverArtArchive {
    enum Failure: Error { case missing, invalidResponse }

    private static let session = URLSession(configuration: .ephemeral)

    static func releaseID(from input: String) -> UUID? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: value) { return id }
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme),
              ["musicbrainz.org", "www.musicbrainz.org"].contains(url.host?.lowercased()),
              url.pathComponents.count >= 3, url.pathComponents[1] == "release" else { return nil }
        return UUID(uuidString: url.pathComponents[2])
    }

    static func releaseArtworkPage(_ id: UUID) -> URL {
        URL(string: "https://musicbrainz.org/release/\(id.uuidString.lowercased())/cover-art")!
    }

    static func releaseSearch(for album: WallAlbum) -> URL {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "musicbrainz.org"
        url.path = "/search"
        url.queryItems = [
            .init(name: "query", value: [album.title, album.artist].compactMap { $0 }.joined(separator: " ")),
            .init(name: "type", value: "release")
        ]
        return url.url!
    }

    static func downloadBack(for release: UUID, session: URLSession? = nil) async throws -> Data {
        let base = "https://coverartarchive.org/release/\(release.uuidString.lowercased())/back-"
        do {
            return try await downloadImage(URL(string: base + "1200")!, session: session)
        } catch Failure.missing {
            return try await downloadImage(URL(string: base + "500")!, session: session)
        }
    }

    static func downloadImage(_ url: URL, session: URLSession? = nil) async throws -> Data {
        let request = URLRequest(url: url, timeoutInterval: 10)
        let (data, response) = try await (session ?? Self.session).data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if response.statusCode == 404 { throw Failure.missing }
        guard response.statusCode == 200, response.url?.scheme == "https",
              response.mimeType?.hasPrefix("image/") == true, data.count <= 8_000_000 else {
            throw Failure.invalidResponse
        }
        return data
    }
}
