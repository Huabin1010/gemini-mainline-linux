#!/usr/bin/env bash
# Post-process gemini Ubuntu 26.04 rootfs (hostname, fstab, console, overlay).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${ROOTFS:-$ROOT/out/rootfs}"
FW_SRC="$ROOT/firmware/gemini"
OVERLAY="$ROOT/rootfs-overlay"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

[[ -d "$ROOTFS/bin" ]] || { echo "rootfs missing — run scripts/build-rootfs.sh first" >&2; exit 1; }

echo "==> hostname + hosts"
echo XiaoMi5-Ubuntu > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1 localhost XiaoMi5-Ubuntu gemini
::1       localhost ip6-localhost ip6-loopback
EOF

echo "==> fstab (UFS userdata by partlabel; UUID changes after flash)"
cat > "$ROOTFS/etc/fstab" <<'EOF'
/dev/disk/by-partlabel/userdata  /  ext4  defaults,noatime  0  1
tmpfs  /tmp   tmpfs  defaults,nodev,nosuid  0  0
tmpfs  /run   tmpfs  defaults,nodev,nosuid  0  0
EOF

echo "==> firmware"
install -d "$ROOTFS/lib/firmware/qcom/msm8996/gemini"
install -d "$ROOTFS/lib/firmware/ath10k"
if [[ -d "$ROOT/inventory/firmware/qcom" ]]; then
	cp -a "$ROOT/inventory/firmware/qcom/." "$ROOTFS/lib/firmware/qcom/"
fi
if [[ -d "$FW_SRC" ]]; then
	find "$FW_SRC" -maxdepth 1 -type f \( -name '*.mbn' -o -name '*.mdt' -o -name '*.b0?' \) \
		-exec cp -a {} "$ROOTFS/lib/firmware/qcom/msm8996/gemini/" \;
fi
if [[ -d "$FW_SRC/ath10k" ]]; then
	cp -a "$FW_SRC/ath10k/." "$ROOTFS/lib/firmware/ath10k/"
fi
for f in regulatory.db regulatory.db.p7s; do
	if [[ -f /lib/firmware/$f ]]; then
		install -m 644 "/lib/firmware/$f" "$ROOTFS/lib/firmware/"
	fi
done

echo "==> drop ginkgo serial getty if copied"
rm -f "$ROOTFS/etc/systemd/system/getty.target.wants/serial-getty@ttyMSM0.service"

echo "==> overlay"
if [[ -d "$OVERLAY" ]]; then
	cp -a "$OVERLAY/." "$ROOTFS/"
fi
chmod 755 "$ROOTFS/usr/local/sbin/"* 2>/dev/null || true
chmod 440 "$ROOTFS/etc/sudoers.d/"* 2>/dev/null || true

echo "==> user hhb1010"
if ! grep -q '^hhb1010:' "$ROOTFS/etc/passwd"; then
	chroot "$ROOTFS" useradd -m -s /bin/bash -G sudo,video,render,input,adm hhb1010 || \
		chroot "$ROOTFS" useradd -m -s /bin/bash -G sudo hhb1010
fi
if ! grep -q '^umeko:' "$ROOTFS/etc/passwd"; then
	chroot "$ROOTFS" useradd -m -s /bin/bash -G sudo,video,render,input umeko || \
		chroot "$ROOTFS" useradd -m -s /bin/bash -G sudo umeko
fi
chroot "$ROOTFS" passwd -d umeko >/dev/null || true

PASS_FILE="$OVERLAY/etc/gemini-root-password"
if [[ -n "${GEMINI_ROOT_PASSWORD:-}" ]]; then
	echo "root:${GEMINI_ROOT_PASSWORD}" | chroot "$ROOTFS" chpasswd
	echo "hhb1010:${GEMINI_ROOT_PASSWORD}" | chroot "$ROOTFS" chpasswd
elif [[ -f "$PASS_FILE" ]]; then
	PW="$(tr -d '\n' < "$PASS_FILE")"
	echo "root:${PW}" | chroot "$ROOTFS" chpasswd
	echo "hhb1010:${PW}" | chroot "$ROOTFS" chpasswd
else
	echo "warn: no GEMINI_ROOT_PASSWORD; serial autologin is hhb1010"
fi

if command -v systemctl >/dev/null && [[ -d "$ROOTFS/bin" ]]; then
	chroot "$ROOTFS" systemctl enable ssh.service 2>/dev/null || true
	chroot "$ROOTFS" systemctl enable NetworkManager 2>/dev/null || true
	chroot "$ROOTFS" systemctl enable display-unblank.service 2>/dev/null || true
	chroot "$ROOTFS" systemctl enable gemini-resize-root.service 2>/dev/null || true
	chroot "$ROOTFS" systemctl enable serial-getty@ttyGS0.service 2>/dev/null || true
	chroot "$ROOTFS" systemctl mask usb-gadget-rndis.service 2>/dev/null || true
	chroot "$ROOTFS" systemctl mask gdm.service gdm3.service 2>/dev/null || true
	chroot "$ROOTFS" systemctl mask KlipperScreen.service xwayland_ks.service 2>/dev/null || true
fi

# Do not enable ginkgo RNDIS (steals the single UDC from g_serial).
rm -f "$ROOTFS/etc/systemd/system/sysinit.target.wants/usb-gadget-rndis.service" \
	"$ROOTFS/etc/systemd/system/multi-user.target.wants/usb-gadget-rndis.service"

echo "==> Done post-install"
du -sh "$ROOTFS"
