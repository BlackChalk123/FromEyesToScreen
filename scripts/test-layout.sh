#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/ModuleCache"
TASK_FLAGS=(--cache-path "$TASK_ROOT/.build/cache" --config-path "$TASK_ROOT/.build/config" --security-path "$TASK_ROOT/.build/security" --disable-sandbox)
swift build -c release "${TASK_FLAGS[@]}"
TASK_BIN="$(swift build -c release "${TASK_FLAGS[@]}" --show-bin-path)"
TASK_APP="$TASK_ROOT/.build/checks/LayoutRegression.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
TASK_SOURCES=()
for TASK_SOURCE in Sources/EyesToScreen/*.swift; do
    if [[ "$TASK_SOURCE" != *EyesToScreenApp.swift ]]; then TASK_SOURCES+=("$TASK_SOURCE"); fi
done
swiftc -parse-as-library -O -g -swift-version 5 -I "$TASK_BIN/Modules" \
    "${TASK_SOURCES[@]}" Tests/LayoutRegression/LayoutRegression.swift \
    "$TASK_BIN"/MotionCore.build/*.swift.o "$TASK_BIN"/MediaCore.build/*.swift.o \
    -o "$TASK_APP/Contents/MacOS/LayoutRegression"
cp "$TASK_ROOT/.build/assets/Example.mov" "$TASK_APP/Contents/Resources/Example.mov"
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.fromeyestoscreen.layout-regression</string>
<key>CFBundleName</key><string>随视布局回归检查</string>
<key>CFBundleExecutable</key><string>LayoutRegression</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$TASK_APP"
"$TASK_APP/Contents/MacOS/LayoutRegression"
python3 -c 'import json,sys; r=json.load(open(".build/checks/layout-regression-result.json")); print(json.dumps(r,ensure_ascii=False)); sys.exit(0 if r["success"] else 1)'
