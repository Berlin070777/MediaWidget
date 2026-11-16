#!/bin/bash
# 小组件外观离屏验证工具（开发用，不参与 App 构建）。
# 用法: ./tools/widget-preview/run.sh
# 产物: /tmp/mwpreview/*.png
#   - *-light/dark.png : ImageRenderer 布局预览
#   - glass-*.png      : 在独立窗口中预览布局
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

echo "== 布局预览 + 逻辑断言 =="
swiftc -O tools/widget-preview/layout-preview.swift "${SRC[@]}" \
  "${FRAMEWORKS[@]}" -target arm64-apple-macos14.0 -o "$OUT/layout-preview"
"$OUT/layout-preview"

echo "== 窗口布局捕获 =="
swiftc -O tools/widget-preview/glass-capture.swift "${SRC[@]}" \
  "${FRAMEWORKS[@]}" -framework CoreGraphics -target arm64-apple-macos14.0 -o "$OUT/glass-capture"
"$OUT/glass-capture"

echo "完成，预览位于 $OUT"
