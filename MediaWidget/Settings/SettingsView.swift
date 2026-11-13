// SettingsView.swift
// MediaWidget
//
// Settings window for the media widget app.

import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: MediaMonitor
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            aboutView
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 420, height: 320)
    }

    // MARK: - General Settings

    private var generalSettings: some View {
        Form {
            Section("常规") {
                Toggle("开机时启动", isOn: $launchAtLogin)
                Toggle("在 Dock 中显示", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
            }

            Section("快捷键") {
                HStack {
                    Text("显示/隐藏浮动面板")
                    Spacer()
                    Text("⌘⇧M")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            Section("监控状态") {
                HStack {
                    Text("MediaRemote 框架")
                    Spacer()
                    if monitor.bridge != nil {
                        Label("已加载", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("不可用", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }

                HStack {
                    Text("监控状态")
                    Spacer()
                    Text(monitor.isMonitoring ? "运行中" : "已停止")
                        .foregroundStyle(monitor.isMonitoring ? .green : .secondary)
                }

                if !monitor.currentMedia.isEmpty {
                    HStack {
                        Text("当前来源")
                        Spacer()
                        Text(monitor.currentMedia.sourceName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About

    private var aboutView: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.accent)

            Text("MediaWidget")
                .font(.title)
                .fontWeight(.bold)

            Text("macOS 全局媒体控制小组件")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                infoRow("版本", value: "1.0.0")
                infoRow("支持来源", value: "网易云音乐、哔哩哔哩、浏览器等")
                infoRow("技术", value: "MediaRemote (私有框架)")
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
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }
}
