# 可行性与验收

2026 年 11 月 13 日，本机为 MacBook Air M2（arm64），macOS 26.2（25C56），Xcode 26.2（17C52），Swift 6.2.3，XcodeGen 2.46。安装了网易云音乐 3.1.12、哔哩哔哩 1.17.1、Safari 26.2 和 Chrome 151。签名版使用本机现有 Apple Development 证书。系统辅助功能和 Safari 网站访问均由用户授权。

## 两份工程的比较

原工程是共同基线。DS 分支在它之上修好 Swift 6 构建、补齐 WidgetKit 扩展声明及沙盒签名，已有菜单栏、悬浮窗口和登录项。其问题集中在数据可信度与控制目标。网易云的原实现从历史时间戳推算播放和进度，面板与 Widget 把指令发给系统的 Now Playing 目标，`allSources` 实际只装了一条记录。B 站尚无专门适配。继续使用 DS 分支，改为按来源读取与执行命令，并删除运行时演示数据。

## 路线调研

| 路线 | 结论 |
| --- | --- |
| WidgetKit | 公开 API。通知中心和桌面可以放置小、中、大尺寸。系统预算及视图归档决定刷新频率，连续拖动和音量滑块放在独立面板。 [刷新调度](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date) |
| App Intents | 公开 API。Widget 按钮使用 App Intent 写入带来源和媒体 ID 的原子指令文件，Darwin 通知唤醒常驻 App，轮询负责补收。App 会校验命令时效、当前来源、条目及能力。 [交互组件](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) |
| App Groups | 公开 API。开发团队签名的主 App、Widget 与 Safari 扩展使用同一 Team ID 组，本机已验证主 App 与 Safari Native Handler 可以读写组容器。ad-hoc 开发回退依赖 Widget 容器保护行为。 [App Group](https://developer.apple.com/documentation/xcode/accessing-app-group-containers) |
| MediaRemote | 私有接口。独立编译的未授权探针在本机网易云播放时返回 0 个字段，Apple 签名的 Swift 解释器运行相同探针可返回系统字段。符号可加载和返回元数据是两件事。公开的 Now Playing API 面向应用发布自己的会话。成品不包含私有框架调用、Apple 签名宿主绕行或 SIP 变更。 [公开 Now Playing](https://developer.apple.com/documentation/NowPlaying) · [MediaRemote 兼容性记录](https://github.com/ungive/mediaremote-adapter) |
| AppleScript / ScriptingBridge | 公开自动化机制，具体能力由目标应用脚本字典决定。网易云及 B 站客户端安装包没有脚本字典。浏览器有脚本字典，但需要 Apple Events 授权及开启 JavaScript 注入；本产品只在可选 Apple Music / Spotify 适配器中使用 AppleScript。 |
| Accessibility | 公开 API，需用户授权。网易云原生控制菜单和 B 站客户端 Chromium 控件可以读取。后台只查询已定位的控件，B 站窗口变化时进行有界发现，找不到控件时降低发现频率。 [辅助功能 API](https://developer.apple.com/documentation/applicationservices/axuielement_h) |
| Media Session 与浏览器扩展 | 公开网页 API。真实 B 站测试视频提供媒体元数据，视频标签报告实际播放及时间。扩展直接使用这些信息，绕开系统会话是否对第三方可读的不确定性。Chrome 通过 Native Messaging 传输，Safari 通过内嵌 Web Extension 和 App Group。 [Media Session](https://www.w3.org/TR/mediasession/) · [Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) · [Safari Native Messaging](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension) |
| Core Audio | 公开 API。能读可用输出设备的音量或静音属性。本机设备分别验证了主通道和虚拟主通道读取。音频输出流只说明进程在做 I/O，不能推出当前曲目、媒体进度或是否暂停。 |
| 触控板手势 | 原生右边缘手势继续打开通知中心。悬浮面板提供全局快捷键和 URL，第三方手势工具可以映射这两个入口，本机没有安装并验证第三方映射。 |

## 支持矩阵

| 来源 | 状态和元数据 | 播放 / 暂停 | 上一项 / 下一项 | 进度与媒体音量 |
| --- | --- | --- | --- | --- |
| 网易云音乐 | 已验证可用：从菜单读取实时状态。部分支持：近期播放记录提供歌名、歌手、专辑、时长及封面链接，恢复旧曲或记录延迟时可能为空。 | 已验证可用：新版面板和后台指令均观察到状态切换。需辅助功能。 | 部分支持：两个原生菜单项可调用。旧曲恢复后存在菜单接受但数据库未及时确认曲目变化的情况。 | 当前不可用：未读到可靠的实时播放位置和绝对媒体音量。 |
| B 站客户端 | 部分支持：真实视频窗口读取标题和播放器时间标签。部分视频提供明确暂停状态，其他情况下按实际时间标签变化判定。 | 需要辅助功能。部分支持：AXPress 对播放器控件返回成功。部分场景未观察到实际状态切换。 | 当前不可用。 | 部分支持：读取进度和时长。拖动与媒体音量未实现。 |
| Chrome B 站 | 已验证可用：标题、作者、播放状态、时长、位置、音量、封面 URL。需要安装扩展。 | 已验证可用。 | 当前不可用。 | 已验证可用：测试视频准确跳到 66 秒，媒体音量写入并读回 32%。 |
| Safari B 站 | 已验证可用：授权后，两个真实标签页分别写入标题、作者、状态、位置和时长。 | 已验证可用：真实视频通过桥接播放和暂停。 | 当前不可用。 | 已验证可用：活动视频跳到 72 秒，音量写入并读回 36%。后台标签页会受 WebKit 节流。 |
| Apple Music / Spotify | 已接入 AppleScript，尚未测试。需要对应播放器自动化授权。 | 尚未测试。 | 尚未测试。 | 尚未测试。 |
| 系统输出 | 已验证可用：音量和静音读取。 | — | — | 写入视输出设备而定。 |

## 集成验收

- Xcode 已生成工程并构建主程序、WidgetKit 扩展、Safari 扩展和 Chrome Native Host。开发签名通过递归验证，PlugInKit 注册了新版两个扩展。
- 实际媒体测试使用播放器自身界面和真实 B 站网页。Widget 指令入口使用同格式文件与 Darwin 通知验证了后台链路和过期来源拒绝。通知中心已显示中号 Widget。用户初次点击在系统 Intent 执行阶段失败，最新复测见 1.2.0。
- 悬浮面板显示了同时检测到的浏览器和桌面来源，已手动从 Chrome 切换到 Safari。面板通过 URL 打开已验证。系统输出音量由面板从 62.5% 调至 72.5%，随后恢复到 62.5%。
- 短时采样中，关闭重型操作时主 App 在 39 MB 物理内存左右，三次 CPU 采样为 0.0%、0.1%、2.3%。这是一组短时采样。
- 已实现应用启动、退出和系统睡眠／唤醒监听，媒体快照有过期时间。真实系统睡眠／唤醒尚未测试。
- Chrome 和 Safari 扩展不使用浏览历史、录屏、OCR 或全站权限。播放状态和短时指令保留在本机。WebKit 可能节流后台页定时器。 [WebKit 页面节流](https://webkit.org/blog/8970/how-web-content-can-affect-power-usage/)


## 1.2.0 封面复测

- 2026 年 11 月 14 日，实机升级至 macOS 27.2.1（26B131），继续使用 Xcode 26.2 构建。
- 用真实视频验证了 B 站封面接口及 CDN 图片，ImageIO 生成最长边 320 像素的 JPEG。Safari 视频与客户端视频切换后，系统的中号 Widget 时间线分别读取到 16,574 和 44,653 字节的不同封面。客户端在悬浮面板已验证暂停、恢复和播放进度。
- 通知中心播放控制改为 `AudioPlaybackIntent`，签名产物的主应用与 Widget 均提取到了系统播放协议元数据。直接调用同一 Intent 后，确认真实 Safari 视频由播放变为暂停，指令入队和主应用路由均有日志。新版通知中心的物理按钮点击尚未确认。
- 网易云原有辅助功能授权仍可读到播放状态。macOS 容器保护拒绝本机读取曲目数据库，已增加文件夹选择入口，授权后需播放一首刚开始的曲目再验证封面。
- 从正在播放的 Safari 会话读取真实封面，离屏渲染并检查了小、中、大三种布局。离屏渲染验证外观，系统时间线日志验证中号 Widget 确实收到封面。
