#!/usr/bin/env bash
# Ubuntu 26.04 arm64 rootfs for gemini.
# Prefer copying Kernel-Build's already-bootstrapped resolute tree (same suite).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${ROOTFS:-$ROOT/out/rootfs}"
SUITE="${SUITE:-resolute}"
MIRROR="${MIRROR:-http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports}"
GINKGO_ROOTFS="${GINKGO_ROOTFS:-$ROOT/../Kernel-Build/out/rootfs}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

command -v debootstrap >/dev/null || {
	echo "error: debootstrap missing (apt install debootstrap qemu-user-static)" >&2
	exit 1
}

if [[ -d "$ROOTFS/bin" ]]; then
	echo "Rootfs already exists at $ROOTFS"
	exit 0
fi

mkdir -p "$(dirname "$ROOTFS")"

if [[ -d "$GINKGO_ROOTFS/bin" ]]; then
	echo "==> Copying Ubuntu 26.04 tree from Kernel-Build ($GINKGO_ROOTFS)"
	cp -a "$GINKGO_ROOTFS" "$ROOTFS"
	echo "==> Done copy: $ROOTFS"
	du -sh "$ROOTFS"
	exit 0
fi

echo "==> debootstrap $SUITE arm64 -> $ROOTFS"
debootstrap --arch=arm64 --variant=minbase \
	"$SUITE" "$ROOTFS" "$MIRROR"

echo "==> Installing essentials"
chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
	systemd systemd-sysv openssh-server sudo \
	network-manager iproute2 iputils-ping \
	kmod udev ca-certificates python3 e2fsprogs

echo "==> Done: $ROOTFS"
du -sh "$ROOTFS"
