#!/usr/bin/env bash
# Host unit tests for Wi-Fi join / switch / password / forget flow.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/out/tests"
mkdir -p "$OUT"

echo "==> C flow"
gcc -O2 -Wall -Wextra -o "$OUT/test-wifi-flow" \
	"$ROOT/tests/wifi-flow/test-wifi-flow.c"
"$OUT/test-wifi-flow"

echo "==> connect.sh"
chmod +x "$ROOT/tests/wifi-flow/fake-nmcli" \
	"$ROOT/tests/wifi-flow/test-gemini-wifi-connect.sh" \
	"$ROOT/rootfs-overlay/usr/local/sbin/gemini-wifi-connect.sh"
"$ROOT/tests/wifi-flow/test-gemini-wifi-connect.sh"

echo "==> wifi-flow tests passed"
