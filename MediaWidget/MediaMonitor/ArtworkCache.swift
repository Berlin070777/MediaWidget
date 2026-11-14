import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ArtworkCache {
    private static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "MediaWidget/Thumbnails-v2")

    static func cached(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: file(url)), !data.isEmpty else { return nil }
        return data
    }

    static func download(_ url: URL) async -> Bool {
        guard isImageURL(url) || isBilibiliMetadataURL(url) else { return false }
        if cached(url) != nil { return true }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: ArtworkRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        do {
            let imageURL = try await resolve(url, session: session)
            let (bytes, response) = try await session.bytes(from: imageURL)
            guard let finalURL = response.url, isImageURL(finalURL),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  response.mimeType?.hasPrefix("image/") == true,
                  response.expectedContentLength <= 8_000_000 else { return false }
            let data = try await collect(bytes, limit: 8_000_000)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 320
                  ] as CFDictionary) else { return false }
            let thumbnail = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(thumbnail, UTType.jpeg.identifier as CFString, 1, nil)
            else { return false }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.83] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return false }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try (thumbnail as Data).write(to: file(url), options: .atomic)
            prune()
            return true
        } catch { return false }
    }

    static func bilibiliReference(videoID: String) -> URL? {
        guard videoID.range(of: #"^BV[0-9A-Za-z]{10}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(videoID)")
    }

    private struct BilibiliResponse: Decodable {
        struct Video: Decodable { let bvid: String; let pic: String }
        let data: Video?
    }

    private static func resolve(_ url: URL, session: URLSession) async throws -> URL {
        guard isBilibiliMetadataURL(url) else { return url }
        let (bytes, response) = try await session.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url == url else {
            throw URLError(.badServerResponse)
        }
        let responseData = try await collect(bytes, limit: 256_000)
        guard let metadata = try JSONDecoder().decode(BilibiliResponse.self, from: responseData).data,
              bilibiliReference(videoID: metadata.bvid) == url,
              var image = URLComponents(string: metadata.pic) else { throw URLError(.cannotDecodeContentData) }
        image.scheme = "https"
        image.query = nil
        image.fragment = nil
        guard let imageURL = image.url, isImageURL(imageURL) else { throw URLError(.badURL) }
        return imageURL
    }

    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    private static func isBilibiliMetadataURL(_ url: URL) -> Bool {
        guard let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value else {
            return false
        }
        return bilibiliReference(videoID: id) == url
    }

    fileprivate static func isImageURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { return false }
        return ["music.126.net", "hdslb.com", "scdn.co"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func file(_ url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).description
        return directory.appending(path: String(hash.suffix(64)) + ".jpg")
    }

    private static func prune() {
        let key = URLResourceKey.contentModificationDateKey
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [key])) ?? []
        guard files.count > 96 else { return }
        let sorted = files.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
        for old in sorted.dropFirst(80) { try? FileManager.default.removeItem(at: old) }
    }
}

private final class ArtworkRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(ArtworkCache.isImageURL) == true ? request : nil)
    }
}
