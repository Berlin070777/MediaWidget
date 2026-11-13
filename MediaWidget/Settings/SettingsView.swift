// SettingsView.swift
// MediaWidget
//
// Settings window for the media widget app.

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var monitor: MediaMonitor

    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("demoMode") private var demoMode = false

    /// Mirrors `SMAppService.mainApp.status`; `SMAppService` can only be toggled
    /// asynchronously, so the UI state is kept in a separate `@State`.
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("通用", systemImage: "gear") }

            aboutView
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 540)
        .onAppear(perform: syncLaunchAtLoginState)
    }

    // MARK: - General

    private var generalSettings: some View {
        Form {
            Section("常规") {
                Toggle("开机时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        applyLaunchAtLogin(newValue)
                    }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("在 Dock 中显示图标", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }

                Toggle("演示模式（显示示例曲目）", isOn: $demoMode)
                    .onChange(of: demoMode) { _, _ in
                        monitor.refreshNowPlaying()
                    }
            }

            Section("快捷键") {
                HStack {
                    Text("显示 / 隐藏悬浮面板")
                    Spacer()
                    Text("⌘ ⇧ M")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }

            Section("运行状态") {
                statusRow(
                    "MediaRemote 框架",
                    ok: monitor.bridge != nil,
                    okText: "已加载",
                    failText: "不可用"
                )
                statusRow(
                    "监控中",
                    ok: monitor.isMonitoring,
                    okText: "是",
                    failText: "否"
                )
                HStack {
                    Text("当前数据源")
                    Spacer()
                    Text(monitor.activeSourceLabel)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)

                statusRow(
                    "后台共享存储",
                    ok: AppGroupStatus.isAvailable,
                    okText: "App Group",
                    failText: "本地文件兜底"
                )
                HStack {
                    Text("当前播放源")
                    Spacer()
                    Text(monitor.currentMedia.isEmpty ? "—" : monitor.currentMedia.sourceName)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)

                HStack {
                    Text("共享数据路径")
                    Spacer()
                    Text(AppGroupStatus.storagePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func statusRow(_ title: String, ok: Bool, okText: String, failText: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Label(ok ? okText : failText, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .labelStyle(.titleAndIcon)
        }
        .font(.callout)
    }

    // MARK: - About

    private var aboutView: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("MediaWidget")
                .font(.title)
                .fontWeight(.bold)

            Text("macOS 菜单栏 / 桌面媒体控制小组件")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                infoRow("版本", value: Self.appVersion)
                infoRow("支持来源", value: "Apple Music、Spotify、网易云、QQ音乐、浏览器等")
                infoRow("技术", value: "MediaRemote (私有框架) + WidgetKit")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Spacer()

            Text("⚠️ 使用私有 API，仅供个人使用，不可上架 App Store")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Launch at Login

    private func syncLaunchAtLoginState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        launchAtLoginError = nil
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "设置失败：\(error.localizedDescription)（请先把 App 移到「应用程序」文件夹）"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Shared storage diagnostics

/// Reports which shared-storage backend the app is currently using.
enum AppGroupStatus {
    /// `true` when the App Group container is actually available.
    static var isAvailable: Bool {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.appGroupID
        ) else { return false }
        return FileManager.default.isWritableFile(atPath: container.path)
    }

    /// Human-readable location of the shared state.
    static var storagePath: String {
        if isAvailable {
            return "App Group: \(Constants.appGroupID)"
        }
        return SharedDefaults.fallbackFileURL.path
    }
}
