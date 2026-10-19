#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ ! -d "$TASK_ROOT/build/随视.app" ]; then
    /bin/bash "$TASK_ROOT/scripts/build.sh"
fi
open "$TASK_ROOT/build/随视.app"
