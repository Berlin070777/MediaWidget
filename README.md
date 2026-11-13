# MediaWidget

macOS 菜单栏应用和通知中心小组件，支持检测及控制网易云音乐、哔哩哔哩客户端，以及 Chrome 和 Safari 的 B 站视频。菜单栏和悬浮面板能切换当前控制来源。缺失的字段显示「不可用」。

## 在本机使用

1. 在此 Mac 上打开「应用程序」中的 `MediaWidget.app`。自行构建时，运行 `build/Build/Products/Release/MediaWidget.app` 或把它安装到固定位置，只保留一个运行实例。
2. 在菜单栏打开控制界面，或按 **⌘⇧M** 打开悬浮面板。面板也可由 `open 'mediawidget://panel'` 打开。
3. 在「系统设置 → 隐私与安全性 → 辅助功能」添加并启用这个构建位置的 MediaWidget，随后打开网易云或哔哩哔哩客户端开始播放。应用保持在菜单栏时，小组件持续接收快照。
4. 点屏幕右上角日期时间，或用两指从触控板右边缘向左滑打开通知中心。点击底部「编辑小组件」，搜索「媒体控制」或「MediaWidget」，选中号或大号。桌面右键菜单也可添加。
5. 播放多个来源时，在菜单栏或悬浮面板的「播放源」菜单里选择；「自动选择」优先显示正在播放的来源，同状态下按网易云、B 站客户端、Safari、Chrome、Apple Music、Spotify 排序。点击标题打开来源。

### Chrome

1. 在 MediaWidget 设置的「播放源与权限」点「配置 Chrome 扩展」。它会写入当前用户的 Native Messaging host 清单，并在访达中定位打包好的 `ChromeExtension` 目录。
2. 打开 `chrome://extensions`，开启开发者模式，点「加载已解压的扩展程序」，选择上述目录。
3. 打开或刷新 `www.bilibili.com/video/…` 或 `www.bilibili.com/bangumi/play/…` 页面。移动 App 后，重新配置 Chrome 并重载扩展目录。使用自定义 `--user-data-dir` 时，Chrome 从对应目录下的 `NativeMessagingHosts` 查找清单。

### Safari

1. 使用带 App Group 的签名版。设置中点「打开 Safari 扩展设置」，或进入「Safari → 设置 → 扩展」。
2. 启用「MediaWidget · B站」。在该扩展的「编辑网站」中把 `bilibili.com` 设为「允许」，或在 B 站页通过工具栏扩展菜单授权此网站。
3. 刷新 B 站视频页并播放。在独立 Safari 用户场景中，按其权限设置启用扩展。

### 可选权限

- 网易云和哔哩哔哩客户端使用辅助功能。若 macOS 提示访问其他 App 的数据，该授权只影响读取网易云本地 SQLite 曲目信息，菜单播放控制可以独立使用。
- Apple Music 和 Spotify 集成默认关闭。打开后，只对正在运行的播放器发出 Apple Events，并由 macOS 请求对应的「自动化」权限。
- 封面下载默认关闭。打开后，仅在需要时请求媒体站点的图片 CDN，并将缩略图缓存到本机。
- 「登录时启动」使用 `SMAppService`。需要固定安装位置时，可把签名 App 放入「应用程序」。
- 可在已经安装的手势工具中把手势映射到 `⌘⇧M` 或 `mediawidget://panel`。MediaWidget 直接通过 macOS 的原生右滑通知中心入口显示 Widget。

## 构建

需要 Xcode 26.2、Swift 6.2 和 XcodeGen。部署目标是 macOS 14，实际测试环境见 [可行性与验收](docs/verification.md)。

```bash
xcodegen generate
open MediaWidget.xcodeproj
```

`./build-local.sh` 构建本地 ad-hoc Release。要生成带 App Group 的 App、Widget 和 Safari 扩展，先在钥匙串中准备 Apple Development 证书，然后运行：

```bash
MEDIA_WIDGET_TEAM=你的团队ID ./build-local.sh
```

该脚本使用 macOS 的 `TEAMID.com.mediawidget.shared` 组，并对三个目标使用同一个开发团队。输出位于 `build/Build/Products/Release/MediaWidget.app`。ad-hoc 构建使用 Widget 沙盒容器作为开发回退，macOS 的容器保护可能阻止共享，Safari 桥接需要带 App Group 的签名版。[Apple App Group 文档](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)

## 实现与限制

| 功能 | 行为 |
| --- | --- |
| 通知中心 Widget | 小、中、大三尺寸。中、大尺寸显示已知进度。App Intents 按钮包含来源和媒体标识，常驻 App 读取后校验并路由。WidgetKit 控制刷新频率，1 倍速且有明确时长时可使用系统计时进度条。 |
| 悬浮面板 | 可按来源选择、打开来源应用、调节系统音量。媒体支持时可拖动进度及调节独立音量。 |
| 网易云客户端 | 从自身「控制」菜单读取播放状态并调用相应动作。歌名、歌手、专辑和时长来自观察到的近期本地记录，记录缺失、延迟或无法关联时显示不可用。没有可依赖的实时进度和绝对媒体音量接口。 |
| B 站客户端 | 辅助功能适配当前客户端的一处视频窗口，识别播放器和时间标签。网页 DOM 类名随客户端更新可能变化。进度拖动和绝对媒体音量目前未实现。 |
| B 站网页 | Chrome 和 Safari 扩展读取视频元素及页面公开的媒体元数据。支持逐标签页控制播放、暂停、进度和音量。当前未接入分 P 或播放列表的上／下一项按钮。 |
| 其他媒体 | Apple Music / Spotify 走显式启用的 AppleScript 适配器。QQ 音乐、IINA、VLC、YouTube 暂未接入。 |
| 本地处理 | 只共享当前快照和短时指令。扩展仅注入 B 站点播或番剧视频页，权限声明没有历史记录 API、全站访问或录屏。 |
| 平台边界 | 普通第三方 App 没有公开接口可枚举所有系统媒体会话。MediaWidget 通过各来源适配器聚合，运行时不调用 MediaRemote。 |

小组件被 macOS 保留在屏幕上的旧快照可能持续到下一次系统刷新。后台退出后旧指令会过期，后台重新启动时不会执行。此构建是本机开发签名，未进行 Developer ID 签名、公证或商店分发。

更多环境、验证结果和未测项目见 [可行性与验收](docs/verification.md)。
