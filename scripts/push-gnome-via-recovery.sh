#!/usr/bin/env bash
# Install rootfs-overlay onto userdata from TWRP (adb recovery).
# This is the way to persist userspace files on 6.1 without ram-booting 7.0.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY="$ROOT/rootfs-overlay"

adb devices | grep -q recovery || {
	echo "error: phone is not in TWRP (adb recovery)." >&2
	echo "Mi 5: 关机后按 电源+音量+ 进 TWRP，USB 连上再跑本脚本。" >&2
	adb devices -l
	exit 1
}

echo "==> Mount userdata"
adb shell 'mount /data; mkdir -p /data/usr/local/sbin /data/etc/systemd/system /data/etc/gdm3 /data/etc/X11/xorg.conf.d /data/etc/environment.d /data/etc/dconf/profile /data/etc/dconf/db/local.d /data/etc/sudoers.d /data/etc/ssh/sshd_config.d /data/var/lib'

echo "==> Push overlay"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Host uid 1000 in the tarball makes sudo reject /etc/sudoers.d.
tar --owner=0 --group=0 -C "$OVERLAY" -czf "$tmp/overlay.tgz" .
adb push "$tmp/overlay.tgz" /tmp/gemini-overlay.tgz
adb shell 'tar -xzf /tmp/gemini-overlay.tgz -C /data && rm /tmp/gemini-overlay.tgz'

run() { adb shell "$1"; }

echo "==> Permissions, getty, mask (short adb shells; TWRP segfaults on long ones)"
run 'chmod 755 /data/usr/local/sbin/reboot-fastboot /data/usr/local/sbin/gemini-gnome-setup.sh /data/usr/local/sbin/display-unblank.sh'
run 'install -d /data/usr/local/bin /data/home/umeko/Desktop /data/usr/share/applications'
run 'install -d /data/etc/systemd/system/getty.target.wants /data/etc/systemd/system/multi-user.target.wants /data/etc/systemd/system/graphical.target.wants'
run 'ln -sfn ../sbin/reboot-fastboot /data/usr/local/bin/reboot-fastboot'
run 'chmod 755 /data/home/umeko/Desktop/reboot-fastboot.desktop /data/usr/share/applications/reboot-fastboot.desktop'
run 'chown -R 0:0 /data/etc/sudoers.d'
run 'chmod 755 /data/etc/sudoers.d'
run 'chmod 440 /data/etc/sudoers.d/99-gemini-reboot-fastboot'
run 'chown 0:0 /data/usr/local/sbin/reboot-fastboot'
run 'rm -f /data/etc/systemd/system/multi-user.target.wants/autottyGS0.service /data/etc/systemd/system/autottyGS0.service'
run 'ln -s /dev/null /data/etc/systemd/system/autottyGS0.service'
run 'ln -sfn /lib/systemd/system/serial-getty@.service /data/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service'
run 'ln -sfn /etc/systemd/system/gemini-gnome-setup.service /data/etc/systemd/system/multi-user.target.wants/gemini-gnome-setup.service'
run 'ln -sfn /etc/systemd/system/display-unblank.service /data/etc/systemd/system/graphical.target.wants/display-unblank.service'
run 'ln -sfn /dev/null /data/etc/systemd/system/KlipperScreen.service'
run 'ln -sfn /dev/null /data/etc/systemd/system/xwayland_ks.service'
run 'ln -sfn /dev/null /data/etc/systemd/system/usb-gadget-rndis.service'
run 'rm -f /data/etc/systemd/system/sysinit.target.wants/usb-gadget-rndis.service'

echo "==> Overlay is on userdata (/data = Ubuntu root)."
echo "TWRP Reboot → System 回 6.1，或进 fastboot 再 ram-boot 7.0。"
