#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/ModuleCache"
TASK_FLAGS=(--cache-path "$TASK_ROOT/.build/cache" --config-path "$TASK_ROOT/.build/config" --security-path "$TASK_ROOT/.build/security" --disable-sandbox)
swift build --product Suishi -c release "${TASK_FLAGS[@]}"
TASK_BIN="$(swift build -c release "${TASK_FLAGS[@]}" --show-bin-path)"
TASK_APP="$TASK_ROOT/build/随视 1.0.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources" "$TASK_ROOT/build/Symbols"
cp "$TASK_BIN/Suishi" "$TASK_APP/Contents/MacOS/Suishi.new"
mv -f "$TASK_APP/Contents/MacOS/Suishi.new" "$TASK_APP/Contents/MacOS/Suishi"
cp "$TASK_ROOT/Configuration/Suishi-Info.plist" "$TASK_APP/Contents/Info.plist"
if [ ! -f "$TASK_ROOT/.build/assets/AppIcon.icns" ]; then
    mkdir -p "$TASK_ROOT/.build/assets"
    swift "$TASK_ROOT/scripts/make-assets.swift" "$TASK_ROOT/.build/assets"
fi
cp "$TASK_ROOT/.build/assets/AppIcon.icns" "$TASK_APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.fromeyestoscreen.suishi "$TASK_APP"
TASK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")"
xcrun dsymutil "$TASK_BIN/Suishi" -o "$TASK_ROOT/build/Symbols/随视-$TASK_VERSION.dSYM"
printf '\n已构建正式版首版：%s\n' "$TASK_APP"
