#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

build_args=()
if [[ -n "${MEDIA_WIDGET_TEAM:-}" ]]; then
    build_args+=(
        "CODE_SIGN_IDENTITY=Apple Development"
        "DEVELOPMENT_TEAM=$MEDIA_WIDGET_TEAM"
        "MEDIA_WIDGET_APP_GROUP=${MEDIA_WIDGET_TEAM}.com.mediawidget.shared"
        "MEDIA_WIDGET_ENTITLEMENT_SUFFIX=.AppGroup"
    )
fi

xcodegen generate
if (( ${#build_args[@]} )); then
    xcodebuild -project MediaWidget.xcodeproj -scheme MediaWidget -configuration Release \
        -destination "platform=macOS,arch=$(uname -m)" ONLY_ACTIVE_ARCH=YES -derivedDataPath build "${build_args[@]}" build
else
    xcodebuild -project MediaWidget.xcodeproj -scheme MediaWidget -configuration Release \
        -destination "platform=macOS,arch=$(uname -m)" ONLY_ACTIVE_ARCH=YES -derivedDataPath build build
fi
codesign --verify --deep --strict build/Build/Products/Release/MediaWidget.app
