import Foundation
import ImageIO
import UniformTypeIdentifiers

actor AlbumArtwork {
    static let shared = AlbumArtwork()

    struct Request: Hashable, Sendable {
        let url: URL
        let version: String
    }

    private let thumbnails: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 18 * 1024 * 1024
        return cache
    }()

    func thumbnail(_ request: Request) -> CGImage? {
        let key = "\(request.url.path)#\(request.version)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard !Task.isCancelled, let image = Self.decode(request.url, maxPixels: 672) else { return nil }
        thumbnails.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    func widgetThumbnail(_ request: Request) -> Data? {
        guard !Task.isCancelled, let image = Self.decode(request.url, maxPixels: 256) else { return nil }
        return Self.jpeg(image, quality: 0.82)
    }

    func importedBackArtwork(_ file: URL) -> Data? {
        let accessed = file.startAccessingSecurityScopedResource()
        defer { if accessed { file.stopAccessingSecurityScopedResource() } }
        guard let image = Self.decode(file, maxPixels: 1200) else { return nil }
        return Self.jpeg(image, quality: 0.91)
    }

    func downloadedBackArtwork(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = Self.decode(source, maxPixels: 1200) else { return nil }
        return Self.jpeg(image, quality: 0.91)
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func decode(_ file: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return decode(source, maxPixels: maxPixels)
    }

    private static func decode(_ source: CGImageSource, maxPixels: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}
