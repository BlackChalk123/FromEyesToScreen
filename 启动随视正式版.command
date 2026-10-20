#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
# Always perform an incremental build so this launcher cannot silently open an old binary.
/bin/bash "$TASK_ROOT/scripts/build-v1.sh"
open "$TASK_ROOT/build/随视 1.0.app"
