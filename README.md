# MediaWidget

> 一个常驻 macOS 菜单栏 / 桌面的流媒体播放状态小组件 —— 实时显示当前在播内容，并提供播放控制。

基于 **SwiftUI + WidgetKit + MediaRemote**，通过私有框架读取系统「正在播放」信息，用 App Group 在主 App 与 Widget 扩展之间共享数据。

> ⚠️ 项目仍在开发中，当前状态见 [已知问题](#-已知问题)。

---

## ✨ 功能特性

| 模块 | 说明 | 状态 |
|---|---|---|
| 菜单栏常驻 | `MenuBarExtra` 弹出面板，图标随播放状态变化（`play.fill` / `play`） | ✅ 已实现 |
| 播放信息展示 | 标题 / 艺术家 / 专辑 / 封面 / 进度 / 音量 | ✅ 已实现 |
| 播放控制 | 播放·暂停 / 上一曲 / 下一曲 / 拖动进度 / 音量 | ✅ 已实现 |
| 悬浮面板 | 全局快捷键 `⌘⇧M` 呼出无边框毛玻璃浮动窗口，可置顶所有空间 | ✅ 已实现 |
| 桌面小组件 | WidgetKit 中小/大尺寸，展示当前媒体并提供 AppIntent 控制按钮 | ✅ 已实现 |
| 设置项 | 开机启动、Dock 显示、快捷键说明、框架加载状态 | ✅ 已实现 |
| 多音源切换 | `allSources` 数据已采集 | 🚧 待做 UI |
| 自定义主题 / 封面开关 | 常量与 Key 已预留 | 🚧 待做 |

### 已知支持的应用

通过 MediaRemote 读取**系统级** Now Playing，理论上覆盖所有向系统注册的播放器：

- Apple Music、Spotify、IINA、VLC
- 网易云音乐（额外用 AppleScript 菜单点击作为兜底）
- QQ 音乐、哔哩哔哩、Safari / Chrome 网页播放

---

## 🧱 技术架构

```
┌──────────────────────────┐        App Group         ┌───────────────────────────┐
│   MediaWidget.app        │  group.com.mediawidget   │  MediaWidgetExtension     │
│   (菜单栏 / 悬浮面板)     │  .shared (UserDefaults)  │  (WidgetKit 桌面小组件)    │
├──────────────────────────┤ ◀──────────────────────▶ ├───────────────────────────┤
│ MediaMonitor  ───────────┼── 写 JSON ───────────────▶│ TimelineProvider 读取      │
│      │                   │                          │                           │
│ MediaRemoteBridge        │                          │ MediaIntents              │
│  (dlopen 私有框架)        │                          │  (dlopen 私有框架)         │
│      │                   │                          │      │                    │
│ MediaController ─────────┼── 发送播放指令 ───────────┼──────┘                    │
└──────────────────────────┘                          └───────────────────────────┘
```

### 目录结构

```
MediaWidget/
├── project.yml                     # XcodeGen 工程定义（唯一工程配置来源）
├── Shared/                         # 双 target 共享代码
│   ├── MediaInfo.swift             # 核心数据模型（Codable / Sendable）
│   ├── Constants.swift             # App Group、WidgetKind、MediaRemote 指令码、已知 App
│   └── SharedDefaults.swift        # App Group 读写封装（JSON 序列化）
├── MediaWidget/                    # 主 App target
│   ├── App/
│   │   ├── MediaWidgetApp.swift    # @main，MenuBarExtra + Settings
│   │   └── AppDelegate.swift       # Carbon 全局热键、NSPanel 悬浮窗
│   ├── MediaMonitor/
│   │   ├── MediaMonitor.swift      # 状态中枢（@MainActor ObservableObject）
│   │   └── MediaRemoteBridge.swift # 运行期 dlopen/CFBundle 加载私有框架
│   ├── MediaController/            # 播放控制 + AppleScript 兜底
│   ├── Views/                      # MenuBarView / FloatingPanelView
│   ├── Settings/                   # SettingsView
│   └── MediaWidget.entitlements
└── MediaWidgetExtension/           # 小组件 target
    ├── MediaWidgetBundle.swift     # WidgetBundle 入口
    ├── MediaWidget.swift           # StaticConfiguration + TimelineProvider
    ├── MediaIntents.swift          # 播放/暂停、上/下一曲、打开来源 App
    ├── Views/MediaWidgetView.swift
    └── MediaWidgetExtension.entitlements
```

### 关键技术点

- **私有框架 MediaRemote**：不链接任何私有 header，运行时通过 `dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote")` 取符号，编译期无需 SDK，代价是非 App Store 分发方式。
- **App Group 通信**：`SharedDefaults` 用 `UserDefaults(suiteName: "group.com.mediawidget.shared")` 传 JSON，Widget 到期刷新时直接读缓存。
- **时间戳校正**：播放进度用 `positionTimestamp` 推算，避免每秒轮询。
- **签名**：目前 `CODE_SIGN_IDENTITY: "-"`（ad-hoc）+ 手写 entitlements，本地跑通后需换成真实开发团队签名，否则 App Group 容器可能不可用。

---

## 🚀 环境要求

- macOS 14.0+（Sonoma）
- Xcode 16.2+（本项目在 Xcode 26.2 / SDK 26.2 上验证）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
```

---

## 🛠 快速开始

```bash
git clone https://github.com/Berlin070777/MediaWidget.git
cd MediaWidget

# 1. 生成 Xcode 工程（.xcodeproj 不入库，必须先生成）
xcodegen generate

# 2. 打开
open MediaWidget.xcodeproj
```

在 Xcode 中选择 `MediaWidget` scheme → Run。

> 💡 **改了 `project.yml` 或增删了源文件，都要重新执行 `xcodegen generate`**。
> 仓库刻意忽略 `*.xcodeproj/`，避免出现工程文件与 `project.yml` 不一致导致的诡异编译错误。

命令行构建：

```bash
xcodegen generate
xcodebuild -project MediaWidget.xcodeproj \
           -scheme MediaWidget \
           -configuration Debug \
           build
```

### 运行前配置

1. **App Group**：把 `Constants.appGroupID`、两份 `.entitlements` 里的 `group.com.mediawidget.shared` 换成你账号下已注册的 App Group
2. **Bundle ID**：`project.yml` 里的 `com.mediawidget.app` / `com.mediawidget.app.widget`
3. **签名**：`project.yml` 中 `CODE_SIGN_IDENTITY` 与 `DEVELOPMENT_TEAM` 换成你的开发者证书
4. **小组件添加**：运行一次 App 后，右键桌面 → 编辑小组件 → 搜索「媒体控制」

---

## 🚧 已知问题

当前代码处于 **编译修复阶段**，`xcodegen generate` + `xcodebuild` 尚有报错待处理：

### 1. 已修复：工程文件过期

| 现象 | 原因 | 处理 |
|---|---|---|
| `error: Multiple commands produce .../MediaWidget.swiftmodule` | 入库的 `.xcodeproj` 生成于 `PRODUCT_MODULE_NAME` 加入 `project.yml` 之前，两个 target 模块名都为 `MediaWidget` | 重新 `xcodegen generate` 即可（`.xcodeproj` 现已加入 `.gitignore` 防止复发） |

### 2. 待修：Swift 6 严格并发

| 位置 | 错误 |
|---|---|
| `MediaWidgetExtension/MediaIntents.swift:47-85` | `static property 'title'/'description'/'openAppWhenRun' is not concurrency-safe because it is nonisolated global shared mutable state`<br>→ 静态属性为 `var` 且非 `@MainActor`，需改为 `@MainActor static var` 或标注 `nonisolated(unsafe)` |
| `Shared/SharedDefaults.swift:16` | `stored property 'defaults' of 'Sendable'-conforming struct 'SharedDefaults' has non-Sendable type 'UserDefaults'`<br>→ 移除无谓的 `Sendable` 约束，或改存 `suiteName` 按需取 |

### 3. 运行时风险

- ad-hoc 签名下 App Group 容器可能创建失败，`SharedDefaults` 会走 `assertionFailure` 分支
- 私有 API `MediaRemote` 在系统升级后符号名可能变动，`MediaRemoteBridge` 已做 `nil` 保护但功能会静默失效

---

## 🗺 Roadmap

- [ ] 修复 Swift 6 并发报错，跑通首次构建
- [ ] 接入真实开发者签名，验证 App Group 共享
- [ ] 多音源切换 UI（`MediaMonitor.allSources` 已就绪）
- [ ] 小组件支持 `.systemSmall` 紧凑布局（`CompactPlayerWidget` kind 已预留）
- [ ] 主题与封面显示开关落库
- [ ] 开机自启动改用 `SMAppService`

---

## ⚠️ 免责声明

本项目使用 **Apple 私有框架 `MediaRemote`** 与 `NSAppleScript` 控制播放，仅用于个人学习与研究：

- 无法上架 Mac App Store
- 不受 Apple 官方支持，系统更新可能导致失效
- 请自行承担使用风险

媒体元数据与封面版权归各自内容提供方所有。

---

## 📄 License

尚未指定。在补充 LICENSE 前，默认保留所有权利（All rights reserved）。
