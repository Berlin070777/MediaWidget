import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ArtworkCache {
    private static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "MediaWidget/Thumbnails-v2")

    static func cached(_ url: URL) -> Data? { try? Data(contentsOf: file(url)) }

    static func download(_ url: URL) async -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              ["music.126.net", "hdslb.com", "scdn.co"].contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { return false }
        if cached(url) != nil { return true }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  response.mimeType?.hasPrefix("image/") == true,
                  response.expectedContentLength <= 8_000_000 else { return false }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 8_000_000 else { return false }
                data.append(byte)
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 320
                  ] as CFDictionary) else { return false }
            let thumbnail = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(thumbnail, UTType.jpeg.identifier as CFString, 1, nil)
            else { return false }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return false }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try (thumbnail as Data).write(to: file(url), options: .atomic)
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            if files.count > 96 {
                let sorted = files.sorted {
                    let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return lhs > rhs
                }
                for old in sorted.dropFirst(80) { try? FileManager.default.removeItem(at: old) }
            }
            return true
        } catch { return false }
    }

    private static func file(_ url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).description
        return directory.appending(path: String(hash.suffix(64)) + ".jpg")
    }
}
