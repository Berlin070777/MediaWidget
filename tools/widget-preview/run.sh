#!/bin/bash
# 小组件外观离屏验证工具（开发用，不参与 App 构建）。
# 用法: ./tools/widget-preview/run.sh
# 产物: /tmp/mwpreview/*.png
#   - layout-*.png / *-light/dark.png : ImageRenderer 布局预览（玻璃降级为材质，见下）
#   - glass-*.png                     : 真实窗口合成器捕获的原生液态玻璃
# 说明: ImageRenderer 无法渲染系统 Liquid Glass 合成器，故布局预览用 DEBUG 材质降级
#       (WidgetGlassPreview.forceMaterialFallback) 显示几何；真实玻璃用 glass-capture
#       在独立 NSWindow 中 hosting 后以 CGWindowListCreateImage 捕获自身窗口（无需录屏权限）。
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=/tmp/mwpreview
mkdir -p "$OUT"

SRC=(
  MediaWidgetExtension/Views/MediaWidgetView.swift
  MediaWidgetExtension/Views/WidgetGlassStyle.swift
  MediaWidgetExtension/MediaWidget.swift
  Shared/Constants.swift
  Shared/MediaInfo.swift
  Shared/MediaIntents.swift
  Shared/SharedDefaults.swift
)
FRAMEWORKS=(-framework SwiftUI -framework WidgetKit -framework AppIntents -framework AppKit)

echo "== 布局预览 + 逻辑断言 (DEBUG 材质降级) =="
swiftc -O -DDEBUG tools/widget-preview/layout-preview.swift "${SRC[@]}" \
  "${FRAMEWORKS[@]}" -target arm64-apple-macos14.0 -o "$OUT/layout-preview"
"$OUT/layout-preview"

echo "== 真实液态玻璃窗口捕获 =="
swiftc -O tools/widget-preview/glass-capture.swift "${SRC[@]}" \
  "${FRAMEWORKS[@]}" -framework CoreGraphics -target arm64-apple-macos14.0 -o "$OUT/glass-capture"
"$OUT/glass-capture"

echo "完成，预览位于 $OUT"