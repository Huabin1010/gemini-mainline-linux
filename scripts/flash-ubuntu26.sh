#!/usr/bin/env bash
# Flash Ubuntu 26.04 userdata + 7.0 boot. Wipes the old Ubuntu 20.04 rootfs.
# Do not flash ginkgo dtbo/vbmeta onto gemini.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-$ROOT/out/rootfs.ext4}"
BOOTIMG="${BOOTIMG:-$ROOT/out/boot.img}"

export PATH="$HOME/.local/bin:$PATH"

[[ -f "$IMAGE" ]] || { echo "missing $IMAGE — run scripts/build-rootfs-image.sh" >&2; exit 1; }
[[ -f "$BOOTIMG" ]] || { echo "missing $BOOTIMG — run scripts/build-bootimg.sh" >&2; exit 1; }

fastboot devices | grep -q . || { echo "error: no fastboot device (18d1:d00d)" >&2; exit 1; }
prod=$(fastboot getvar product 2>&1 | awk '/product:/{print $2; exit}')
echo "==> product=$prod"
if [[ "$prod" != "gemini" && "$prod" != "lithium" ]]; then
	echo "warn: product is '$prod' (expected gemini). Continuing because serial may still match."
fi

echo "==> flash userdata (erases Ubuntu 20.04 on sda15)"
fastboot flash userdata "$IMAGE"
echo "==> flash boot (7.0 + initramfs overlay)"
fastboot flash boot "$BOOTIMG"
echo "==> reboot"
fastboot reboot
echo "Wait for ACM 0525:a4a7. Green+yellow = display-unblank. Vol+ = reboot-fastboot."
