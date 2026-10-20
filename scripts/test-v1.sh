#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/ModuleCache"
mkdir -p .build/checks
TASK_FLAGS=(--cache-path "$TASK_ROOT/.build/cache" --config-path "$TASK_ROOT/.build/config" --security-path "$TASK_ROOT/.build/security" --disable-sandbox)
swift build --product Suishi -c debug "${TASK_FLAGS[@]}"
TASK_BIN="$(swift build -c debug "${TASK_FLAGS[@]}" --show-bin-path)"
swiftc -parse-as-library -swift-version 5 -I "$TASK_BIN/Modules" \
    Sources/Suishi/Preferences.swift Sources/Suishi/RecentStore.swift Sources/Suishi/WindowPlacement.swift Tests/SuishiTests/CoreChecks.swift \
    "$TASK_BIN"/RotationCore.build/*.swift.o "$TASK_BIN"/MediaCore.build/*.swift.o \
    -o .build/checks/suishi-core-checks
.build/checks/suishi-core-checks
if [ "${1:-}" = "--core-only" ]; then exit 0; fi
TASK_APP="$TASK_ROOT/.build/checks/SuishiIntegration.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
TASK_SOURCES=()
for TASK_SOURCE in Sources/Suishi/*.swift; do
    if [[ "$TASK_SOURCE" != *SuishiApp.swift ]]; then TASK_SOURCES+=("$TASK_SOURCE"); fi
done
swiftc -parse-as-library -swift-version 5 -I "$TASK_BIN/Modules" \
    "${TASK_SOURCES[@]}" Tests/SuishiTests/IntegrationChecks.swift \
    "$TASK_BIN"/RotationCore.build/*.swift.o "$TASK_BIN"/MediaCore.build/*.swift.o \
    -o "$TASK_APP/Contents/MacOS/SuishiIntegration"
cp "$TASK_ROOT/.build/assets/Example.mov" "$TASK_APP/Contents/Resources/Example.mov"
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.fromeyestoscreen.suishi.integration</string>
<key>CFBundleExecutable</key><string>SuishiIntegration</string>
<key>CFBundleName</key><string>随视首版检查</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$TASK_APP"
"$TASK_APP/Contents/MacOS/SuishiIntegration"
python3 -c 'import json,sys; r=json.load(open(".build/checks/suishi-integration.json")); print(json.dumps(r,ensure_ascii=False)); sys.exit(0 if r["success"] else 1)'
