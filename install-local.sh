#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

source_app="$PWD/build/Build/Products/Release/MediaWidget.app"
target=/Applications/MediaWidget.app
backup_root="$HOME/Library/Application Support/MediaWidget"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
extensions=(MediaWidgetExtension SafariExtension)

if [[ ! -x "$lsregister" ]]; then
    printf 'LaunchServices registration tool unavailable: %s\n' "$lsregister" >&2
    exit 1
fi
codesign --verify --deep --strict "$source_app"
mkdir -p "$backup_root"
upgrade="$(mktemp -d "$backup_root/install.XXXXXX")"
incoming="$upgrade/incoming"
backup="$upgrade/previous"
mkdir "$incoming" "$backup"
ditto "$source_app" "$incoming/MediaWidget.app"

stop_executable() {
    local executable="$1" pid attempt
    while IFS= read -r pid; do
        kill -TERM "$pid" 2>/dev/null || true
        for ((attempt = 0; attempt < 40; attempt++)); do
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            printf 'Could not stop %s (PID %s)\n' "$executable" "$pid" >&2
            return 1
        fi
    done < <(ps -axo uid=,pid=,comm= | awk -v executable="$executable" -v user="$(id -u)" '
        $1 == user { pid = $2; sub(/^ *[0-9]+ +[0-9]+ +/, ""); if ($0 == executable) print pid }
    ')
}

# macOS can retain a running extension after its .appex has been replaced.
# Stop this app's processes by exact executable path so WidgetKit launches
# the new extension instead of asking the old one to render the new bundle.
for app in "$target" "$source_app"; do
    stop_executable "$app/Contents/MacOS/MediaWidget"
    for extension in "${extensions[@]}"; do
        stop_executable "$app/Contents/PlugIns/$extension.appex/Contents/MacOS/$extension"
    done
done

if [[ -d "$target" ]]; then mv "$target" "$backup/MediaWidget.app"; fi
if ! mv "$incoming/MediaWidget.app" "$target"; then
    if [[ -d "$backup/MediaWidget.app" ]]; then
        mv "$backup/MediaWidget.app" "$target"
        open "$target"
    fi
    exit 1
fi

"$lsregister" -u "$source_app" 2>/dev/null || true
"$lsregister" -f "$target"
for extension in "${extensions[@]}"; do
    pluginkit -r "$source_app/Contents/PlugIns/$extension.appex" 2>/dev/null || true
    pluginkit -a "$target/Contents/PlugIns/$extension.appex"
    # Cover an extension launch racing the replacement.
    stop_executable "$target/Contents/PlugIns/$extension.appex/Contents/MacOS/$extension"
done
open "$target"
printf 'Installed %s\n' "$target"
if [[ -d "$backup/MediaWidget.app" ]]; then
    printf 'Previous app: %s\n' "$backup/MediaWidget.app"
    # Notification Center can retain a failed extension lookup from the
    # replacement window. The per-user agent relaunches with fresh metadata.
    stop_executable /System/Library/CoreServices/NotificationCenter.app/Contents/MacOS/NotificationCenter
fi
