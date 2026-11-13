// DemoMedia.swift
// MediaWidget
//
// Sample media used by SwiftUI previews and by the app's "demo mode",
// which lets the whole UI be inspected without a real player running.
//
// Enable it with:
//   defaults write com.mediawidget.app demoMode -bool YES

import Foundation
#if canImport(AppKit)
import AppKit
#endif

extension MediaInfo {

    /// A sample track with generated artwork, used for previews and demo mode.
    static var demo: MediaInfo {
        MediaInfo(
            sourceID: "com.apple.Music",
            sourceName: "Apple Music",
            title: "La Femme d'Argent",
            artist: "Air",
            album: "Moon Safari",
            artworkData: ArtworkFactory.makeDemoArtwork(),
            duration: 430,
            currentPosition: 96,
            playbackRate: 1,
            volume: 0.7,
            capabilities: .all,
            lastUpdated: .now,
            positionTimestamp: .now
        )
    }

    /// A sample paused track.
    static var demoPaused: MediaInfo {
        var copy = demo
        copy.playbackRate = 0
        return copy
    }
}

// MARK: - ArtworkFactory

/// Draws a placeholder cover image so the demo has something to show.
enum ArtworkFactory {

    /// Renders a 512×512 gradient cover with a music note into JPEG data.
    static func makeDemoArtwork(size: CGFloat = 512) -> Data? {
        #if canImport(AppKit)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let colors = [
            NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.92, alpha: 1),
            NSColor(calibratedRed: 0.86, green: 0.36, blue: 0.62, alpha: 1),
        ]
        let gradient = NSGradient(colors: colors)
        gradient?.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -55)

        // Concentric rings for a retro look.
        NSColor.white.withAlphaComponent(0.12).setStroke()
        for index in 1...5 {
            let radius = size * 0.12 * CGFloat(index)
            let path = NSBezierPath(
                ovalIn: NSRect(
                    x: size / 2 - radius,
                    y: size / 2 - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            path.lineWidth = size * 0.012
            path.stroke()
        }

        if let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.28, weight: .semibold)
            if let tinted = symbol.withSymbolConfiguration(config) {
                tinted.isTemplate = true
                NSColor.white.withAlphaComponent(0.92).set()
                let rect = NSRect(
                    x: (size - tinted.size.width) / 2,
                    y: (size - tinted.size.height) / 2,
                    width: tinted.size.width,
                    height: tinted.size.height
                )
                tinted.draw(in: rect)
            }
        }

        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        #else
        return nil
        #endif
    }
}
