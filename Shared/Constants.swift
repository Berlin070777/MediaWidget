import Foundation

enum Constants {
    static let appGroupID = Bundle.main.object(forInfoDictionaryKey: "MediaWidgetAppGroup") as? String ?? ""
    static let widgetBundleID = "com.mediawidget.app.widget"
    static let widgetKind = "MediaControlWidget"
    static let albumWallWidgetKind = "AlbumWallWidget"
    static let sourcePickerURL = URL(string: "mediawidget://sources")!
    static let albumWallURL = URL(string: "mediawidget://albums")!
    static let commandNotification = "com.mediawidget.app.widget-command.v2"

    enum KnownApp {
        static let neteaseMusic = "com.netease.163music"
        static let bilibili = "com.bilibili.bilibiliPC"
        static let safari = "com.apple.Safari"
        static let chrome = "com.google.Chrome"
        static let appleMusic = "com.apple.Music"
        static let spotify = "com.spotify.client"
    }
}

extension String {
    var nonBlank: String? {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
