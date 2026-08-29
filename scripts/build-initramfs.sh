#!/usr/bin/env bash
# Build gzip cpio initramfs: static /init + rootfs-overlay (USB gadget).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/out"
STAGING="$OUT/initramfs-staging"
IMAGE="$OUT/initramfs.cpio.gz"
INIT_BIN="$OUT/initramfs-init"
CC="${CC:-aarch64-linux-gnu-gcc}"

echo "==> Compiling static aarch64 init"
"$CC" -static -Os -Wall -Wextra -o "$INIT_BIN" "$ROOT/initramfs/init.c"
file "$INIT_BIN"

echo "==> Building initramfs -> $IMAGE"
rm -rf "$STAGING"
mkdir -p "$STAGING"
install -m 755 "$INIT_BIN" "$STAGING/init"
mkdir -p "$STAGING/sbin"
ln -sf ../init "$STAGING/sbin/init"

if [[ -d "$ROOT/rootfs-overlay" ]]; then
	echo "==> Adding rootfs-overlay to initramfs"
	cp -a "$ROOT/rootfs-overlay/." "$STAGING/overlay/"
	rm -f "$STAGING/overlay/etc/gemini-root-password"
		chmod 755 "$STAGING/overlay/usr/local/sbin/usb-gadget-rndis.sh" \
			"$STAGING/overlay/usr/local/sbin/display-unblank.sh" \
			"$STAGING/overlay/usr/local/sbin/gemini-fb-ui.py" \
			"$STAGING/overlay/usr/local/sbin/gemini-gnome-setup.sh" \
			"$STAGING/overlay/usr/local/sbin/gemini-wifi-connect.sh"
		chmod 755 "$STAGING/overlay/usr/sbin/wpa_supplicant" \
			"$STAGING/overlay/usr/sbin/iw" \
			"$STAGING/overlay/usr/sbin/rfkill" 2>/dev/null || true
	if [[ -f "$STAGING/overlay/usr/local/sbin/reboot-fastboot" ]]; then
		chmod 755 "$STAGING/overlay/usr/local/sbin/reboot-fastboot"
		mkdir -p "$STAGING/overlay/usr/local/bin" \
			"$STAGING/overlay/home/hhb1010/Desktop" \
			"$STAGING/overlay/home/umeko/Desktop"
		echo "==> Compiling static aarch64 reboot-bootloader"
		"$CC" -static -Os -Wall -Wextra -o \
			"$STAGING/overlay/usr/local/sbin/reboot-bootloader" \
			"$ROOT/initramfs/reboot-bootloader.c"
		chmod 755 "$STAGING/overlay/usr/local/sbin/reboot-bootloader"
		echo "==> Compiling static aarch64 gemini-fb-ui"
		"$CC" -static -Os -Wall -Wextra -o \
			"$STAGING/overlay/usr/local/sbin/gemini-fb-ui" \
			"$ROOT/initramfs/gemini-fb-ui.c"
		chmod 755 "$STAGING/overlay/usr/local/sbin/gemini-fb-ui"
		GLES_SYS="$ROOT/out/sysroot-aarch64"
		GLES_INC="$GLES_SYS/usr/include"
		GLES_LIB="$GLES_SYS/usr/lib/aarch64-linux-gnu"
		if [[ -f "$GLES_INC/gbm.h" && -f "$GLES_LIB/libEGL.so" &&
		      -f "$GLES_LIB/libGLESv2.so" && -f "$GLES_LIB/libgbm.so" &&
		      -f "$GLES_LIB/libdrm.so" ]]; then
			echo "==> Compiling aarch64 gemini-status (GBM/GLES2)"
			"$CC" -O2 -Wall -Wextra \
				-I"$GLES_INC" -I"$GLES_INC/libdrm" \
				-L"$GLES_LIB" -Wl,-rpath-link,"$GLES_LIB" \
				-o "$STAGING/overlay/usr/local/sbin/gemini-status" \
				"$ROOT/initramfs/gemini-status.c" \
				"$ROOT/initramfs/gemini-status-gpu.c" \
				-lGLESv2 -lEGL -lgbm -ldrm -lm
		else
			echo "==> Compiling static aarch64 gemini-status (no GLES sysroot)"
			"$CC" -static -O2 -Wall -Wextra -o \
				"$STAGING/overlay/usr/local/sbin/gemini-status" \
				"$ROOT/initramfs/gemini-status.c" \
				"$ROOT/initramfs/gemini-status-gpu-stub.c" -lm
		fi
		chmod 755 "$STAGING/overlay/usr/local/sbin/gemini-status"
		file "$STAGING/overlay/usr/local/sbin/gemini-status"
		ln -sfn ../sbin/reboot-fastboot \
			"$STAGING/overlay/usr/local/bin/reboot-fastboot"
		chmod 440 "$STAGING/overlay/etc/sudoers.d/99-gemini-reboot-fastboot" 2>/dev/null || true
		chmod 755 "$STAGING/overlay/home/hhb1010/Desktop/reboot-fastboot.desktop" \
			"$STAGING/overlay/home/umeko/Desktop/reboot-fastboot.desktop" \
			"$STAGING/overlay/usr/share/applications/reboot-fastboot.desktop" 2>/dev/null || true
	fi
	mkdir -p "$STAGING/overlay/etc/systemd/system/"{sysinit.target.wants,multi-user.target.wants,graphical.target.wants,getty.target.wants}
	ln -sfn ../gemini-gnome-setup.service \
		"$STAGING/overlay/etc/systemd/system/multi-user.target.wants/gemini-gnome-setup.service"
	ln -sfn ../display-unblank.service \
		"$STAGING/overlay/etc/systemd/system/graphical.target.wants/display-unblank.service"
	ln -sfn ../display-unblank.service \
		"$STAGING/overlay/etc/systemd/system/multi-user.target.wants/display-unblank.service"
	ln -sfn ../gemini-resize-root.service \
		"$STAGING/overlay/etc/systemd/system/multi-user.target.wants/gemini-resize-root.service"
	# Keys/touch are handled inside display-unblank (Type=simple).
	# GDM/gnome-shell blacks a working MSM fbdev scanout. The status HUD
	# owns the panel (Wi-Fi + meters). Keep GDM masked.
	ln -sfn /dev/null "$STAGING/overlay/etc/systemd/system/gdm.service"
	ln -sfn /dev/null "$STAGING/overlay/etc/systemd/system/gdm3.service"
	ln -sfn /dev/null "$STAGING/overlay/etc/systemd/system/display-manager.service"
	ln -sfn /dev/null "$STAGING/overlay/etc/systemd/system/getty@tty1.service"
	# Only serial-getty@ttyGS0 (autologin drop-in). A second agetty on the
	# same port eats ACM keystrokes (reboot-fastboot becomes ebo-ftoo).
	rm -f "$STAGING/overlay/etc/systemd/system/multi-user.target.wants/autottyGS0.service"
	ln -sfn /dev/null "$STAGING/overlay/etc/systemd/system/autottyGS0.service"
	ln -sfn /lib/systemd/system/serial-getty@.service \
		"$STAGING/overlay/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service"
	ln -sfn /lib/systemd/system/ssh.service \
		"$STAGING/overlay/etc/systemd/system/multi-user.target.wants/ssh.service"
	ln -sfn /dev/null "$STAGING/overlay/etc/systemd/system/KlipperScreen.service"
	ln -sfn /dev/null "$STAGING/overlay/etc/systemd/system/xwayland_ks.service"
	# umeko uses g_serial. Do not let configfs RNDIS steal the UDC.
	ln -sfn /dev/null "$STAGING/overlay/etc/systemd/system/usb-gadget-rndis.service"

	# 7.0 DRM is a module (like 6.1). Only copy display kos so overlay
	# deploy does not dump the whole defconfig module tree onto userdata.
	if [[ -d "$ROOT/out/modules/lib/modules" ]]; then
		echo "==> Adding DRM modules to overlay"
		krel=""
		for d in "$ROOT/out/modules/lib/modules/"*; do
			[[ -d "$d" ]] || continue
			krel=$(basename "$d")
			break
		done
		if [[ -n "$krel" ]]; then
			src="$ROOT/out/modules/lib/modules/$krel"
			dst="$STAGING/overlay/lib/modules/$krel"
			mkdir -p "$dst"
			while IFS= read -r rel; do
				[[ -f "$src/$rel" ]] || continue
				mkdir -p "$dst/$(dirname "$rel")"
				cp -a "$src/$rel" "$dst/$rel"
			done <<'MODS'
kernel/drivers/gpu/drm/msm/msm.ko
kernel/drivers/gpu/drm/panel/panel-jdi-fhd-r63452.ko
kernel/drivers/soc/qcom/ubwc_config.ko
kernel/drivers/gpu/drm/clients/drm_client_lib.ko
kernel/drivers/gpu/drm/drm_gpuvm.ko
kernel/drivers/gpu/drm/drm_exec.ko
kernel/drivers/gpu/drm/display/drm_display_helper.ko
kernel/drivers/media/cec/core/cec.ko
kernel/drivers/gpu/drm/scheduler/gpu-sched.ko
kernel/drivers/gpu/drm/drm_kms_helper.ko
MODS
			cp -a "$src/modules.order" "$src"/modules.builtin* "$dst/" 2>/dev/null || true
			if command -v depmod >/dev/null; then
				depmod -a -b "$STAGING/overlay" "$krel" || true
			fi
		fi
	fi

	# Adreno 530 firmware so msm.ko can probe without waiting on userdata.
	# 6.1 dmesg: a530_pm4.fw / a530_pfp.fw / a530v3_gpmu.fw2 then msmdrmfb.
	if [[ -d "$ROOT/inventory/firmware/qcom" ]]; then
		echo "==> Adding GPU firmware to initramfs"
		mkdir -p "$STAGING/lib/firmware/qcom/msm8996/gemini"
		cp -a "$ROOT/inventory/firmware/qcom/." "$STAGING/lib/firmware/qcom/"
		# Prefer Xiaomi-signed gemini zap from vendor (cust). Never
		# overwrite it with the APQ8096 linux-firmware blob — TZ
		# rejects that with pas_init_image -EIO (-5).
		if [[ -f "$STAGING/lib/firmware/qcom/apq8096/a530_zap.mbn" && \
		      ! -f "$STAGING/lib/firmware/qcom/msm8996/gemini/a530_zap.mbn" ]]; then
			cp "$STAGING/lib/firmware/qcom/apq8096/a530_zap.mbn" \
				"$STAGING/lib/firmware/qcom/msm8996/gemini/a530_zap.mbn"
		fi
		# Also land on userdata via overlay so post-switch_root
		# request_firmware sees the signed zap.
		if [[ -d "$ROOT/rootfs-overlay/lib/firmware/qcom" ]]; then
			mkdir -p "$STAGING/overlay/lib/firmware/qcom"
			cp -a "$ROOT/rootfs-overlay/lib/firmware/qcom/." \
				"$STAGING/overlay/lib/firmware/qcom/"
		fi
	fi
	# QCA6174 is builtin ath10k_pci. Host linux-firmware ships .zst and
	# this kernel has # CONFIG_FW_LOADER_COMPRESS is not set, so the
	# overlay stores uncompressed .bin (see rootfs-overlay/lib/firmware).
	if [[ -d "$ROOT/rootfs-overlay/lib/firmware/ath10k" ]]; then
		echo "==> Adding ath10k firmware to initramfs"
		mkdir -p "$STAGING/lib/firmware"
		cp -a "$ROOT/rootfs-overlay/lib/firmware/ath10k" "$STAGING/lib/firmware/"
		cp -a "$ROOT/rootfs-overlay/lib/firmware/regulatory.db"* \
			"$STAGING/lib/firmware/" 2>/dev/null || true
	fi
fi

(
	cd "$STAGING"
	find . -print0 | cpio --null -o --format=newc
) | gzip -9 >"$IMAGE"

ls -lh "$IMAGE"
