import SwiftUI

struct AlbumSleeve<Front: View>: View, Animatable {
    let album: WallAlbum
    let artwork: NSImage?
    let backArtwork: NSImage?
    var backStatus: AlbumBackArtworkStatus = .noMatch
    let side: CGFloat
    let reflectionHeight: CGFloat
    nonisolated var progress: Double
    let showDetails: () -> Void
    let editBackArtwork: () -> Void
    var retryBackLookup: (() -> Void)? = nil
    @ViewBuilder let front: () -> Front

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let fraction = min(2, max(-1, progress))
        let face = fraction.rounded()
        let isBack = abs(face) == 1
        let tilt = reduceMotion ? 0 : -180 * (fraction - face)
        let reflectionOpacity = 0.21 * (1 - 2 * abs(fraction - face))

        ZStack {
            if isBack { back.transition(.identity) }
            else { front().transition(.identity) }
        }
        .frame(width: side, height: side)
        .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.31)
        .overlay(alignment: .bottom) {
            if let reflection = isBack ? backArtwork : artwork {
                Image(nsImage: reflection)
                    .resizable()
                    .aspectRatio(contentMode: isBack ? .fit : .fill)
                    .frame(width: side, height: side)
                    .clipped()
                    .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.31)
                    .scaleEffect(x: 1, y: -1)
                    .frame(height: reflectionHeight, alignment: .top)
                    .clipped()
                    .mask {
                        LinearGradient(colors: [.white, .white.opacity(0.33), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .blur(radius: 0.8)
                    .opacity(reflectionOpacity)
                    .offset(y: reflectionHeight + 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var back: some View {
        Button(action: showDetails) {
            Group {
                if let backArtwork {
                    Image(nsImage: backArtwork)
                        .resizable()
                        .scaledToFit()
                } else {
                    VStack(spacing: 10) {
                        Text(album.title).font(.headline).lineLimit(2)
                        if let artist = album.artist {
                            Text(artist).font(.subheadline).lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            if backStatus == .searching { ProgressView().controlSize(.small) }
                            Text(backStatus.message)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.top, 6)
                    }
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(18)
                }
            }
            .frame(width: side, height: side)
            .background(Color(white: 0.09))
            .clipShape(.rect(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(album.title) · \(backArtwork == nil ? backStatus.message : "唱片背封")")
        .accessibilityHint("打开专辑详情")
        .contextMenu {
            Button("查看专辑详情", action: showDetails)
            if let source = album.backSourceURL ?? album.backReleaseID.map(CoverArtArchive.releaseArtworkPage) {
                Link("查看背封来源", destination: source)
            }
            if let retryBackLookup, backArtwork == nil, backStatus != .searching {
                Button("重新查找真实背封", action: retryBackLookup)
            }
            Button("添加或更换背封…", action: editBackArtwork)
        }
    }
}
