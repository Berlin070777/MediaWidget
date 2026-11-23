// MediaWidgetApp.swift
// MediaWidget
//
// Main app entry point with a menu bar shortcut.

import SwiftUI

@main
struct MediaWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var mediaMonitor = MediaMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: mediaMonitor, showPlayer: { appDelegate.presentPlayer() },
                        showAlbumWall: { appDelegate.presentAlbumWall() },
                        showSettings: { appDelegate.presentSettings() })
        } label: {
            Image(systemName: mediaMonitor.currentMedia.isPlaying ? "play.fill" : "play")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(monitor: mediaMonitor)
        }
        .commands {
            MediaWindowCommands(monitor: mediaMonitor, appDelegate: appDelegate, library: .shared)
        }
    }
}


private struct MediaWindowCommands: Commands {
    @ObservedObject var monitor: MediaMonitor
    let appDelegate: AppDelegate
    let library: AlbumWallStore

    @AppStorage(AlbumWallLayout.preference) private var layout: AlbumWallLayout = .carousel
    @AppStorage(AlbumWallCollection.preference) private var collection: AlbumWallCollection = .recent
    @AppStorage(AlbumWallStore.historyPreference) private var recordHistory = true

    var body: some Commands {
        CommandMenu("唱片墙") {
            Button("打开唱片墙") { appDelegate.presentAlbumWall() }
                .keyboardShortcut("1")
            Button("搜索唱片…") { appDelegate.presentAlbumSearch() }
                .keyboardShortcut("f")
            Button("定位正在播放的专辑") {
                if let album = library.playingAlbum(for: monitor.currentMedia) { appDelegate.presentAlbum(album) }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(library.playingAlbum(for: monitor.currentMedia) == nil)
            Divider()
            Picker("专辑分组", selection: $collection) {
                ForEach(AlbumWallCollection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("显示方式", selection: $layout) {
                ForEach(AlbumWallLayout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Divider()
            if let album = WallAlbum(media: monitor.currentMedia) {
                Button(library.isFavorite(album.id) ? "取消收藏正在播放的专辑" : "收藏正在播放的专辑") {
                    library.toggleFavorite(album, artwork: monitor.currentMedia.artworkData)
                }
            }
            Toggle("记录最近播放", isOn: $recordHistory)
            Button("清除最近播放…") { appDelegate.confirmClearingRecentAlbums() }
                .disabled(library.recentAlbums.isEmpty)
        }

        CommandMenu("播放") {
            Button("打开媒体控制") { appDelegate.presentPlayer() }
                .keyboardShortcut("2")
            let media = monitor.currentMedia
            transport(media.playPauseCommand, title: media.isPlaying ? "暂停" : "播放", media: media)
            transport(.previous, title: "上一项", media: media)
            transport(.next, title: "下一项", media: media)
            Divider()
            Picker("播放源", selection: Binding(get: { monitor.preferredSource }, set: { _ = monitor.chooseSource($0) })) {
                Text("自动选择").tag("")
                ForEach(monitor.allSources) { source in
                    Text(source.sourceName).tag(source.sourceID)
                }
            }
        }
    }

    private func transport(_ command: MediaCommand, title: String, media: MediaInfo) -> some View {
        Button(title) { monitor.submit(command, for: media) }
            .disabled(!media.capabilities.contains(command.capability))
    }
}
