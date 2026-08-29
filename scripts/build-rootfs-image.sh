#!/usr/bin/env bash
# Create ext4 rootfs image from out/rootfs. Flashing wipes userdata.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${ROOTFS:-$ROOT/out/rootfs}"
IMAGE="${IMAGE:-$ROOT/out/rootfs.ext4}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

[[ -d "$ROOTFS/bin" ]] || { echo "rootfs missing" >&2; exit 1; }

USED_MB=$(du -sm "$ROOTFS" | cut -f1)
SIZE_MB=$(( USED_MB + 768 ))
if [[ "$SIZE_MB" -lt 2048 ]]; then SIZE_MB=2048; fi

echo "==> Creating ${SIZE_MB}MB ext4 image: $IMAGE"
rm -f "$IMAGE"
truncate -s "${SIZE_MB}M" "$IMAGE"
mkfs.ext4 -F -L rootfs "$IMAGE" >/dev/null

MNT=$(mktemp -d)
mount -o loop "$IMAGE" "$MNT"
cp -a "$ROOTFS"/. "$MNT"/
umount "$MNT"
rmdir "$MNT"

ls -lh "$IMAGE"
echo "First boot runs gemini-resize-root to fill the 50G userdata partition."
echo "Flash: ./scripts/flash-ubuntu26.sh"
