import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private let navigation = MediaWindowNavigation()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
            NSApp.dockTile.display()
        }
        MediaMonitor.shared.startMonitoring(
            showPlayer: { [weak self] in self?.presentPlayer() },
            showSources: { [weak self] in self?.presentPlayer(choosingSource: true) }
        )
        if mainWindow == nil, preferencesWindow == nil {
            presentMainWindow(activating: !ProcessInfo.processInfo.arguments.contains("--background"))
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        presentMainWindow()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "mediawidget" {
            switch url.host {
            case "panel": presentPlayer()
            case "sources": presentPlayer(choosingSource: true)
            case "settings": presentSettings()
            case "albums": presentAlbumWall()
            default: break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MediaMonitor.shared.stopMonitoring()
    }

    func presentAlbumWall() {
        navigation.page = .albums
        presentMainWindow()
    }

    func presentAlbumSearch() {
        guard mainWindow?.attachedSheet == nil else { return }
        navigation.isSearchingAlbums = true
        presentAlbumWall()
    }

    func presentAlbum(_ album: WallAlbum) {
        guard mainWindow?.attachedSheet == nil else { return }
        navigation.albumFocus = AlbumWallFocus(albumID: album.id)
        presentAlbumWall()
    }

    func presentPlayer(choosingSource: Bool = false) {
        navigation.isChoosingSource = choosingSource
        navigation.page = .player
        presentMainWindow()
    }

    private func presentMainWindow(activating: Bool = true) {
        if mainWindow == nil {
            let window = MediaMainWindow()
            let content = MediaWindowView(monitor: MediaMonitor.shared, navigation: navigation,
                                          input: window.albumInput)
            window.contentViewController = NSHostingController(rootView: content)
            window.title = "MediaWidget"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.tabbingMode = .disallowed
            window.collectionBehavior = .fullScreenPrimary
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 560, height: 450)
            window.setContentSize(NSSize(width: 880, height: 680))
            window.center()
            window.setFrameAutosaveName("MediaWidgetAlbumWall")
            mainWindow = window
        }
        guard let window = mainWindow else { return }
        if activating {
            show(window)
        } else {
            window.orderBack(nil)
        }
        MediaMonitor.shared.refreshNowPlaying()
    }

    func confirmClearingRecentAlbums() {
        guard let window = mainWindow, window.attachedSheet == nil else { return }
        presentAlbumWall()
        let alert = NSAlert()
        alert.messageText = "清除最近播放？"
        alert.informativeText = "唱片墙将移除最近播放记录，已收藏的专辑会留在「我的收藏」。"
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "清除最近播放").hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { AlbumWallStore.shared.clearRecents() }
        }
    }

    func presentSettings() {
        let window = preferencesWindow ?? NSWindow(
            contentViewController: NSHostingController(rootView: SettingsView(monitor: MediaMonitor.shared))
        )
        if preferencesWindow == nil {
            window.title = "MediaWidget 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        show(window)
    }

    private func show(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
