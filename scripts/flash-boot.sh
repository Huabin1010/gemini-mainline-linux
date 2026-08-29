#!/usr/bin/env bash
# Flash 7.0 boot.img. Requires confirmation. Restores from TWRP if it fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTIMG="${BOOTIMG:-$ROOT/out/boot.img}"
BACKUP="$ROOT/inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img"

export PATH="$HOME/.local/bin:$PATH"

[[ -f "$BOOTIMG" ]] || { echo "missing $BOOTIMG — run scripts/build-bootimg.sh" >&2; exit 1; }

echo "==> Device:"
fastboot devices || true
adb devices -l || true

echo ""
echo "This replaces the boot partition."
echo "Working 6.1 backup: $BACKUP"
echo "Press Ctrl+C to abort, Enter to continue..."
read -r _

if fastboot devices | grep -q .; then
	echo "==> Flashing via fastboot"
	fastboot flash boot "$BOOTIMG"
	fastboot reboot
	exit 0
fi

if adb devices | grep -q recovery; then
	echo "==> Flashing via TWRP adb"
	adb push "$BOOTIMG" /tmp/boot.img
	adb shell dd if=/tmp/boot.img of=/dev/block/bootdevice/by-name/boot
	adb reboot
	exit 0
fi

echo "error: no fastboot or TWRP adb device" >&2
exit 1
