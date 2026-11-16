# 变更记录（Change Log）

本文件记录每次改动的**动机、涉及文件、实现方式、验证与部署**，供接手的人或模型快速理解现状、避免误判。最新条目在上。

阅读顺序建议：先看本文件了解「改了什么、为什么」，再看 [verification.md](verification.md) 了解历史实测与可行性结论，最后看代码。

---

## 1.3.5 · 通知中心进度入口与网易云最小化跳转

- 通知中心把进度显示和跳转入口分开。中号和大号使用带文字的「调整进度」胶囊按钮，小号使用调节图标。
- 网易云 3.1.12 普通窗口最小化时仍可从面板拖动。跳转时临时恢复播放器窗口，完成后恢复最小化。
- 实机点按通知中心的「调整进度」打开面板，验证网易云暂停时可向前、向后拖动，播放器实际位置随之更新。

## 1.3.4 · 拖动进度与玻璃外观

- 通知中心进度条旁新增打开悬浮控制面板的按钮。悬浮面板的原生滑块在松手后提交跳转，以免拖动过程中反复发送指令。
- 本机验证的网易云 3.1.12（3444）普通窗口支持拖动。应用通过辅助功能确认目标窗口，根据播放器实际回报的位置确认跳转。迷你模式中保留进度显示。
- macOS 26 及以上悬浮面板使用 AppKit 液态玻璃。小组件沿用系统玻璃外框，内层按钮和封面背景使用 WidgetKit 可渲染的渐变。

## 1.3.3 · 播放进度

- 读取网易云本地保存的播放位置，只在曲目 ID 匹配时采用该位置。暂停时停止计时，切歌时清除上一首的进度。
- 小、中、大尺寸均可显示进度条。中号和大号同时显示已播时间和总时长。WidgetKit 的原生计时视图在播放中持续更新。
- 实机确认了网易云进度会在同一个小组件快照上前进，暂停和恢复播放时同步停止和继续。

## 1.3.2 · 刷新和播放按钮

- 本机覆盖安装时停止旧的扩展进程，注册新版后让通知中心重新读取扩展。实测解决了版本不匹配导致的时间线更新失败。
- 组件保留系统玻璃外框。内部控件改用可由 WidgetKit 渲染的背景和图标，修复通知中心中的按钮和来源标签消失。
- 选中媒体变化时请求 WidgetKit 刷新。其他来源曲名或播放状态变化不再产生无关的刷新请求。
- 在 macOS 27.2.1 的通知中心实际点击网易云下一首、上一首、暂停和播放，确认播放器和小组件均更新。

## 1.3.1 · 网易云曲目信息恢复

- MediaWidget 重启时会尝试从网易云本地播放记录恢复当前曲目 ID，并匹配同一首歌的元数据和封面。

## 1.3.0 · 液态玻璃外观重设计 + 小组件播放源切换框

### 一句话概述

把 WidgetKit 小组件从「白底 + 灰色 bordered 按钮」重设计为 **macOS 26/27 原生液态玻璃（Liquid Glass）** 外观，并在组件上新增一个**点按即可循环切换播放源**的玻璃胶囊框；主 App 增加对应的指令路由与快照字段。

### 动机

- 原外观朴素（平白容器、`.bordered` 灰按钮），与 macOS 26+ 的系统设计语言脱节。
- 切换播放源原先只能打开悬浮面板（`⌘⇧M`）操作；用户希望直接在小组件上切换。

### 涉及文件

| 文件 | 类型 | 改动 |
| --- | --- | --- |
| `MediaWidgetExtension/Views/MediaWidgetView.swift` | 重写 | 三尺寸液态玻璃布局；玻璃控制簇；播放源胶囊；封面氛围色；进度/空状态重设计；新增 `familyOverride` 预览参数 |
| `MediaWidgetExtension/Views/WidgetGlassStyle.swift` | **新增** | `widgetGlass(in:interactive:tint:)`、`widgetGlassCluster`、`ArtworkPalette`（封面取色）、`WidgetSourceStyle`（来源图标/短名）、`WidgetGlassPreview`（仅 DEBUG 的材质降级开关） |
| `MediaWidgetExtension/MediaWidget.swift` | 修改 | `MediaWidgetEntry` 增加 `sources`/`preferredSource`；Provider 填充；添加画廊展示合成封面的示例；容器背景保持 `.fill.tertiary`（系统自动套玻璃） |
| `Shared/MediaIntents.swift` | 修改 | 新增 `WidgetSourceSwitchIntent`（后台 App Intent）与纯函数 `nextSource(after:in:)` |
| `Shared/SharedDefaults.swift` | 修改 | 新增 `WidgetSourceSummary`；`WidgetSnapshot` 增加 `sources`/`preferredSource`，自定义 `init(from:)` 向后兼容旧 JSON |
| `Shared/MediaInfo.swift` | 修改 | `MediaCommand` 增加 `.selectSource`（capability 为 `[]`） |
| `MediaWidget/MediaMonitor/MediaMonitor.swift` | 修改 | `publish` 写入源列表与首选源并纳入变更检测；`readWidgetCommands` 路由 `.selectSource` → `chooseSource`；首选源失效检查提前到 `updateSelection` 之前 |
| `MediaWidget/MediaMonitor/ScriptingPlayerSource.swift` | 修改 | 穷举 switch 补 `.selectSource: return false` |
| `README.md` | 修改 | 简介补充液态玻璃说明；新增「播放源切换框」用法段落；指向本文件 |
| `tools/widget-preview/` | **新增** | 可复现的离屏布局预览 + 真实玻璃窗口捕获 + 逻辑断言（开发工具，不参与 App 构建） |

此版本同时包含 1.2.1 的网易云曲目授权流程和切歌后封面刷新。

### 新功能：播放源切换框

- 位置：组件左上角玻璃胶囊。内容 = 来源图标 + 名称（自动模式带「自动 ·」前缀，浏览器来源取短名如 `Safari`）+ 播放状态绿点（中/大）+ 循环箭头。
- 交互：**点按循环切换**，顺序为 `自动选择("") → 源1 → 源2 → … → 自动选择`。WidgetKit 不支持 Menu/Picker，故用「循环」而非下拉。
- 数据流：
  1. 胶囊 `Button(intent: WidgetSourceSwitchIntent())`。
  2. Intent 检查共享快照是否仍可用，写入切换指令并发 Darwin 通知。
  3. 主 App 按指令顺序，用当前来源列表和当前选择计算下一个来源（`""` 表示自动）。
  4. `chooseSource` → `updateSelection` → `publish` 回写快照（含新 `preferredSource`）→ `requestWidgetReload` 刷新组件。
  5. Intent 侧轮询等待快照 `preferredSource` 变为目标（最多 ~3.5s）后返回。
- 边界：无来源时胶囊禁用/隐藏；来源已消失时用当前可用列表重新计算；旧快照（无 `sources` 字段）解码为 `[]`/`""`，胶囊禁用，不会崩溃。

### 液态玻璃实现要点

- **容器**：保持 `.containerBackground(.fill.tertiary, for: .widget)`。macOS 26+ 由系统自动套用 Liquid Glass；**不要**试图对 `containerBackground` 直接加 `glassEffect`（无效，见 Apple 文档与社区结论）。
- **内部控件**：`glassEffect(.regular.interactive(), in: Circle()/Capsule())`，播放键额外 `.tint(封面强调色)`；用 `GlassEffectContainer(spacing: 8)` 聚簇。全部包在 `if #available(macOS 26, *)` 内。
- **降级**：macOS 14–25 走 `.ultraThinMaterial` + 白色描边（`widgetGlass` 的 else 分支），布局几何与玻璃分支一致。
- **氛围色**：`ArtworkPalette.from(artworkData)` 把封面降采样到 2×2 取四角均值，得到 top/bottom 渐变与一个饱和度/亮度钳制后的强调色；仅 `widgetRenderingMode == .fullColor` 时启用（accented 模式交给系统着色）。无封面回退 `.accentColor`。
- **accented 模式**：封面保留 `widgetAccentedRenderingMode(.fullColor)`（Apple 建议媒体封面保留全彩）；氛围色在 accented 下不叠加。

### 快照 schema 变更（向后兼容）

`WidgetSnapshot` 新增：
- `sources: [WidgetSourceSummary]`（`sourceID/bundleID/name/title/isPlaying`，不含封面，体积小）
- `preferredSource: String`（`""` = 自动）

自定义 `init(from:)` 用 `decodeIfPresent` 缺省为 `[]`/`""`，因此**旧版主 App 写的快照仍可被新版组件解码**（反之亦然，新增字段被旧解码器忽略）。文件名仍为 `Snapshot-v2.json`，未 bump。

### 预览 / 验证工具（`tools/widget-preview/`）

运行：`./tools/widget-preview/run.sh`，产物在 `/tmp/mwpreview/`。

- `layout-preview.swift`：ImageRenderer 离屏渲染小/中/大 × 亮/暗 × 变体（长标题/固定源/无封面/空状态），并跑逻辑断言（循环切换、旧快照兼容、round-trip、取色）。
  - **关键限制**：ImageRenderer **渲染不了系统 Liquid Glass 合成器**，玻璃元素会整体不可见。因此该脚本设 `WidgetGlassPreview.forceMaterialFallback = true`（仅 DEBUG 存在）改用材质降级来**验证几何布局**。看到玻璃「消失」是工具限制，**不是产品 bug**。
- `glass-capture.swift`：把视图 hosting 进独立 borderless `NSWindow`，用 `CGWindowListCreateImage` 捕获**自身窗口**（无需录屏权限），得到**真实原生玻璃**。需以 macOS 14 为编译 target（该 API 在 15 被标记 obsolete 但运行时仍可用），并设置 `window.appearance` 与内容 colorScheme 一致，否则玻璃跟随系统外观而文字跟随强制外观，产生错配。
- `MediaWidgetView.familyOverride`：因 `\.widgetFamily` 环境只读，离屏渲染需经此参数注入尺寸；生产路径不传（默认 nil → 读环境）。

### 已验证 / 未验证

已验证：
- 四个目标（App / Widget / Safari 扩展 / Chrome Host）Release 构建通过。
- 16 张离屏布局预览无溢出/截断异常；9 项逻辑断言全过。
- 真实窗口玻璃捕获（亮/暗）确认原生材质、对比度、胶囊与控制簇渲染正常。
- 安装后：进程运行、PlugInKit 注册新版扩展、二进制含新代码（`切换播放源`/`selectSource`/`glassEffect`）、共享快照刷新。

未验证（需真实媒体 + 人工操作）：
- 通知中心里**物理点按**切换框的端到端效果（指令链路复用已验证的 `WidgetPlaybackIntent` 机制，逻辑断言覆盖循环规则）。
- 真实桌面壁纸下的玻璃折射观感（捕获用的是窗口背后桌面区域）。

### 构建

运行 `MEDIA_WIDGET_TEAM=YOUR_TEAM_ID ./build-local.sh` 构建开发签名版，让 App、Widget 与 Safari 扩展使用同一个 App Group。完整步骤见 [README](../README.md#从源码构建)。
