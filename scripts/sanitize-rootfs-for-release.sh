#!/usr/bin/env bash
# Copy out/rootfs.ext4 and strip passwords / SSH keys before a public Release.
# Does not modify the original image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$ROOT/out/rootfs.ext4}"
DST="${2:-$ROOT/out/rootfs-release.ext4}"
MNT="${MNT:-/mnt/gemini-rootfs-release}"

[[ -f "$SRC" ]] || { echo "missing $SRC" >&2; exit 1; }
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

echo "==> Copy $SRC -> $DST (sparse)"
cp --sparse=always -f "$SRC" "$DST"
mkdir -p "$MNT"
mount -o loop "$DST" "$MNT"
trap 'umount "$MNT" 2>/dev/null || true' EXIT

rm -f "$MNT/etc/gemini-root-password"
find "$MNT" -path '*/.ssh/authorized_keys' -delete 2>/dev/null || true
find "$MNT" -path '*/.ssh/id_*' -delete 2>/dev/null || true

if [[ -x "$MNT/usr/sbin/chroot" ]] || true; then
	chroot "$MNT" passwd -d root >/dev/null 2>&1 || true
	chroot "$MNT" passwd -d hhb1010 >/dev/null 2>&1 || true
	chroot "$MNT" passwd -d umeko >/dev/null 2>&1 || true
	chroot "$MNT" passwd -e root >/dev/null 2>&1 || true
	chroot "$MNT" passwd -e hhb1010 >/dev/null 2>&1 || true
fi

umount "$MNT"
trap - EXIT
echo "==> Sanitized image: $DST"
echo "    Flash this (or zstd it), not the original out/rootfs.ext4."
