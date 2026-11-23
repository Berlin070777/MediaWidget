import SafariServices
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: MediaMonitor

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
            }
            Section("封面与刷新") {
                Toggle("显示封面", isOn: $showArtwork).onChange(of: showArtwork) { monitor.refreshNowPlaying() }
                Toggle("允许从媒体站点下载封面", isOn: $downloadArtwork)
                    .disabled(!showArtwork)
                    .onChange(of: downloadArtwork) { monitor.refreshNowPlaying() }
                Text("B 站按视频编号查图。翻到唱片背面时，按专辑名和艺人向 MusicBrainz 查图，也会使用已核实的公开图源。播放状态保存在本机。")
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
                LabeledContent("曲目数据库", value: neteaseDatabaseLabel)
                if monitor.neteaseDatabaseStatus == .notConnected {
                    Button("连接网易云曲目信息", action: connectNetease)
                } else {
                    Button("重新检测曲目数据库", action: connectNetease)
                    Button("停用曲目信息") {
                        NeteaseMusicSource.disconnectDatabase()
                        neteaseAccessError = nil
                        monitor.refreshNowPlaying()
                    }
                }
                if monitor.neteaseDatabaseStatus == .permissionRequired {
                    Button("打开文件与文件夹设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Button("选择网易云存储文件夹…", action: chooseNeteaseFolder)
                Text(neteaseAccessError ?? neteaseDatabaseHelp)
                    .font(.caption).foregroundStyle(.secondary)
                if monitor.neteaseDatabaseStatus == .permissionRequired || monitor.neteaseDatabaseStatus == .databaseMissing {
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

    private var neteaseDatabaseLabel: String {
        switch monitor.neteaseDatabaseStatus {
        case .waitingForPlayer: "等待网易云和辅助功能"
        case .notConnected: "未连接"
        case .checking: "正在检查"
        case .readable: "可读取"
        case .permissionRequired: "macOS 已拒绝访问"
        case .databaseMissing: "找不到曲目数据库"
        case .unsupported: "无法识别数据库格式"
        case .temporarilyUnavailable: "暂时无法读取"
        }
    }

    private var neteaseDatabaseHelp: String {
        switch monitor.neteaseDatabaseStatus {
        case .permissionRequired:
            "在「隐私与安全性 → 文件与文件夹」展开 MediaWidget，允许访问网易云应用数据后重新检测。也可尝试选择网易云的 storage 文件夹。"
        case .readable:
            "MediaWidget 会读取网易云保存的当前曲目。若客户端尚未保存曲目信息，切歌后会继续检测。"
        case .databaseMissing:
            "打开网易云并播放一首歌。如果网易云已经在运行，请选择它的 storage 文件夹。"
        case .unsupported:
            "当前网易云版本的记录格式无法识别。播放控制仍可通过辅助功能使用。"
        default:
            "连接后，MediaWidget 只读本地当前曲目及对应记录。macOS 可能会询问是否允许访问网易云的应用数据。"
        }
    }

    private func connectNetease() {
        NeteaseMusicSource.requestDatabaseAccess()
        neteaseAccessError = nil
        Task { await monitor.retryNeteaseDatabaseAccess() }
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
                connectNetease()
            } catch CocoaError.fileReadInvalidFileName {
                neteaseAccessError = "请选择网易云音乐的 storage 文件夹。"
            } catch {
                neteaseAccessError = "无法保存所选文件夹。可在「文件与文件夹」允许访问后重新检测。"
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
