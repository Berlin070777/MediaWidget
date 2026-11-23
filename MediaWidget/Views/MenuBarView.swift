import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: MediaMonitor
    let showPlayer: () -> Void
    let showAlbumWall: () -> Void
    let showSettings: () -> Void
    @State private var isChoosingSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlayerControls(monitor: monitor, artworkSize: 58, isChoosingSource: $isChoosingSource)
            Divider()
            HStack {
                Button("打开媒体控制", systemImage: "macwindow", action: showPlayer)
                Button("唱片墙", systemImage: "square.grid.2x2", action: showAlbumWall)
                    .labelStyle(.titleAndIcon)
                Spacer()
                Button("设置", systemImage: "gearshape") { showSettings() }
                Button("退出", systemImage: "power") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
        }
        .padding(16)
        .frame(width: 330)
        .onAppear { monitor.refreshNowPlaying() }
    }
}

struct ArtworkView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("媒体封面")
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.34, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("封面不可用")
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.15))
    }
}
