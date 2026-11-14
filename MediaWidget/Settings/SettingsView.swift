import SafariServices
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: MediaMonitor

    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("showArtwork") private var showArtwork = true
    @AppStorage("downloadArtwork") private var downloadArtwork = true
    @AppStorage("reducePolling") private var reducePolling = false
    @AppStorage("scriptedPlayers") private var scriptedPlayers = false

    @State private var launchAtLogin = false
    @State private var loginError: String?
    @State private var chromeStatus: String?
    @State private var safariEnabled: Bool?
    @State private var neteaseAccessError: String?

    var body: some View {
        TabView {
            general.tabItem { Label("通用", systemImage: "gear") }
            sources.tabItem { Label("播放源与权限", systemImage: "play.rectangle") }
        }
        .frame(width: 510, height: 500)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            monitor.refreshNowPlaying()
        }
        .task {
            safariEnabled = (try? await SFSafariExtensionManager.stateOfSafariExtension(
                withIdentifier: "com.mediawidget.app.safari"
            ))?.isEnabled
        }
    }

    private var general: some View {
        Form {
            Section("启动与显示") {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { old, new in
                        if new != (SMAppService.mainApp.status == .enabled) { setLaunchAtLogin(new) }
                    }
                if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
                Toggle("在程序坞中显示图标", isOn: $showInDock)
                    .onChange(of: showInDock) { NSApp.setActivationPolicy(showInDock ? .regular : .accessory) }
                LabeledContent("显示或隐藏悬浮面板", value: "⌘ ⇧ M")
            }
            Section("封面与刷新") {
                Toggle("显示封面", isOn: $showArtwork).onChange(of: showArtwork) { monitor.refreshNowPlaying() }
                Toggle("允许从媒体站点下载封面", isOn: $downloadArtwork)
                    .disabled(!showArtwork)
                    .onChange(of: downloadArtwork) { monitor.refreshNowPlaying() }
                Text("按需从内容站点获取封面。B 站客户端使用视频编号查图，播放状态保存在本机。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("降低客户端检测频率", isOn: $reducePolling)
                    .onChange(of: reducePolling) { monitor.refreshNowPlaying() }
            }
            Section("小组件") {
                LabeledContent("共享状态", value: monitor.sharedStorageError ? "写入失败" :
                    SharedDefaults.shared.groupURL == nil ? "本机开发容器" : "App Group")
                Text("打开通知中心，点「编辑小组件」，搜索「媒体控制」。刷新时间由 macOS 调度。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var sources: some View {
        Form {
            Section("网易云音乐与哔哩哔哩客户端") {
                LabeledContent("辅助功能", value: monitor.accessibility ? "已授权" : "待授权")
                Button("打开辅助功能设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Section("网易云曲目与封面") {
                LabeledContent("曲目数据库", value: monitor.neteaseDatabaseReadable == true ? "可读取" :
                                monitor.neteaseDatabaseReadable == false ? "无法读取" : "等待网易云")
                Button("选择网易云存储文件夹…", action: chooseNeteaseFolder)
                Text(neteaseAccessError ?? "选择网易云的 storage 文件夹。若选择器未定位，按 ⌘⇧G 输入下方路径。")
                    .font(.caption).foregroundStyle(.secondary)
                if monitor.neteaseDatabaseReadable != true {
                    Text("~/Library/Containers/com.netease.163music/Data/Documents/storage")
                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Section("浏览器中的 B 站") {
                Button("配置 Chrome 扩展") {
                    do {
                        try ChromeRegistration.register()
                        if let url = ChromeRegistration.extensionURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        chromeStatus = "在 Chrome 的扩展程序页面开启开发者模式，载入选中的 ChromeExtension 文件夹。"
                    } catch { chromeStatus = "注册失败。请确认应用位于固定位置，再重试。" }
                }
                if let chromeStatus { Text(chromeStatus).font(.caption) }

                Button("打开 Safari 扩展设置") {
                    Task {
                        try? await SFSafariApplication.showPreferencesForExtension(
                            withIdentifier: "com.mediawidget.app.safari"
                        )
                    }
                }
                LabeledContent("Safari 扩展", value: safariEnabled == true ? "已启用" : "待启用")
                Text("在 Safari 扩展设置启用 MediaWidget · B站，并允许访问 www.bilibili.com。Safari 使用同一团队签名的 App Group。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("其他播放器") {
                Toggle("连接 Apple Music 和 Spotify", isOn: $scriptedPlayers)
                    .onChange(of: scriptedPlayers) { monitor.refreshNowPlaying() }
                Text("首次连接运行中的播放器时，macOS 会请求自动化权限。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseNeteaseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择网易云音乐的 storage 文件夹"
        panel.message = "MediaWidget 读取这个文件夹中的曲目数据库，以显示歌名和专辑封面。"
        panel.prompt = "授权此文件夹"
        panel.directoryURL = NeteaseMusicSource.storageDirectory.deletingLastPathComponent()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        if panel.runModal() == .OK, let directory = panel.url {
            do {
                try NeteaseMusicSource.storeFolderAccess(directory)
                neteaseAccessError = nil
                monitor.refreshNowPlaying()
            } catch {
                neteaseAccessError = "请选择网易云音乐的 storage 文件夹。"
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
