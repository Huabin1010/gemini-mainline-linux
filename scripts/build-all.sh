#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/setup-kernel.sh"
"$ROOT/scripts/build-kernel.sh"
"$ROOT/scripts/build-bootimg.sh"
ls -lh "$ROOT/out/boot.img"
