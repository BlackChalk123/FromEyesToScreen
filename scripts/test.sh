#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/ModuleCache"
mkdir -p .build/checks
swiftc Sources/MotionCore/*.swift Tests/MotionCoreTests/HeadMotionTests.swift -o .build/checks/motion-tests
.build/checks/motion-tests
swiftc Sources/MotionCore/*.swift Tests/MotionCoreTests/StableMotionTests.swift -o .build/checks/stable-motion-tests
.build/checks/stable-motion-tests
swiftc Sources/MotionCore/*.swift Tests/MotionCoreTests/PresentationTests.swift -o .build/checks/presentation-tests
.build/checks/presentation-tests
swiftc Sources/MotionCore/*.swift Tests/MotionCoreTests/ComfortMotionTests.swift -o .build/checks/comfort-motion-tests
.build/checks/comfort-motion-tests
swiftc Sources/MediaCore/BilibiliVideoLink.swift Sources/MediaCore/BilibiliWebPolicy.swift Tests/MediaCoreTests/BilibiliLinkTests.swift -o .build/checks/bilibili-tests
.build/checks/bilibili-tests
swiftc Sources/EyesToScreen/AppSettings.swift Sources/EyesToScreen/ViewingPresets.swift Tests/SettingsTests/SettingsTests.swift -o .build/checks/settings-tests
.build/checks/settings-tests
