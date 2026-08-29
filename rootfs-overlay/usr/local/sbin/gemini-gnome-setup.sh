#!/bin/bash
# Install Ubuntu GNOME on the existing Focal rootfs and hand the panel to GDM.
# Run as root (TWRP chroot, or first-boot service after NOPASSWD/overlay).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
LOG=/var/log/gemini-gnome-setup.log
exec > >(tee -a "$LOG") 2>&1

echo "==> gemini-gnome-setup $(date -Is || date)"

wait_network() {
	local i
	for i in $(seq 1 3); do
		if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
			return 0
		fi
		# bring up any saved NetworkManager Wi-Fi profiles
		nmcli radio wifi on 2>/dev/null || true
		nmcli networking on 2>/dev/null || true
		nmcli -t -f NAME,TYPE con show 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1}' | while read -r n; do
			nmcli con up "$n" 2>/dev/null || true
		done
		sleep 5
	done
	return 1
}

# Stop Klipper UI from owning the DRM/KMS device.
systemctl stop KlipperScreen.service xwayland_ks.service 2>/dev/null || true
systemctl disable KlipperScreen.service xwayland_ks.service 2>/dev/null || true
systemctl mask KlipperScreen.service xwayland_ks.service 2>/dev/null || true

if command -v gnome-shell >/dev/null && dpkg -s gdm3 >/dev/null 2>&1; then
	echo "==> GNOME already installed"
else
	if ! wait_network; then
		echo "warn: no network, skip GNOME apt; fb-ui keeps the panel"
		exit 0
	fi
	apt-get update
	apt-get install -y \
		ubuntu-desktop-minimal \
		gdm3 \
		gnome-session \
		ubuntu-session \
		mesa-utils \
		libgl1-mesa-dri \
		xserver-xorg-core \
		xserver-xorg-video-fbdev \
		xserver-xorg-video-modesetting \
		dbus-user-session \
		fonts-noto-cjk
fi

# Overlay files may already be in place; keep autologin.
mkdir -p /etc/gdm3
if [[ -f /etc/gdm3/custom.conf ]]; then
	sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf || true
	grep -q AutomaticLoginEnable /etc/gdm3/custom.conf || true
fi

if command -v dconf >/dev/null; then
	dconf update 2>/dev/null || true
fi

# Leave GDM masked; gemini-fb-ui owns the panel.
touch /var/lib/gemini-gnome-setup.done
echo "==> done (GDM left masked)"
