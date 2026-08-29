#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/env.sh
source "$ROOT/scripts/env.sh"

JOBS="${JOBS:-$(nproc)}"
FRAGMENT="$ROOT/config/gemini.fragment"
DEFCONFIG="${DEFCONFIG:-defconfig}"
OUT="$ROOT/out"

die() { echo "error: $*" >&2; exit 1; }

[[ -d "$KERNEL_SRC" ]] || die "kernel source missing at $KERNEL_SRC (run scripts/setup-kernel.sh)"

command -v "${CROSS_COMPILE}gcc" >/dev/null || die "cross compiler not found; run scripts/setup-deps.sh"

"$ROOT/scripts/apply-overlays.sh"

mkdir -p "$KBUILD_OUTPUT" "$OUT"

cd "$KERNEL_SRC"

if [[ -n "${KERNEL_BASE_CONFIG:-}" ]]; then
	echo "==> Base config: $KERNEL_BASE_CONFIG"
	cp "$KERNEL_BASE_CONFIG" "$KBUILD_OUTPUT/.config"
	make O="$KBUILD_OUTPUT" olddefconfig
elif [[ ! -f "$KBUILD_OUTPUT/.config" ]]; then
	echo "==> Initial config: $DEFCONFIG"
	make O="$KBUILD_OUTPUT" "$DEFCONFIG"
fi

if [[ -f "$FRAGMENT" ]]; then
	echo "==> Merging gemini fragment"
	"$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -O "$KBUILD_OUTPUT" \
		"$KBUILD_OUTPUT/.config" "$FRAGMENT"
	make O="$KBUILD_OUTPUT" olddefconfig
	# merge_config may leave defconfig EFI on; LK is not EFI.
	# DRM_MSM as module (6.1): builtin probe can hang on LK splash.
	"$KERNEL_SRC/scripts/config" --file "$KBUILD_OUTPUT/.config" \
		--disable EFI --disable EFI_STUB --disable EFI_GENERIC_STUB \
		--disable EFI_EARLYCON \
		--enable DRM --module DRM_MSM --enable DRM_MSM_MDP5 \
		--enable DRM_MSM_DSI --enable DRM_MSM_DSI_14NM_PHY \
		--disable DRM_MSM_MDP4 --disable DRM_MSM_DPU \
		--disable DRM_MSM_DP --disable DRM_MSM_HDMI \
		--module DRM_PANEL_JDI_R63452 --enable DRM_FBDEV_EMULATION \
		--enable BACKLIGHT_QCOM_WLED \
		--enable USB_G_SERIAL --enable U_SERIAL_CONSOLE
	make O="$KBUILD_OUTPUT" olddefconfig
	# FBINFO_VIRTFB in msm_fbdev lets fbcon paint the same scanout that
	# userspace write(/dev/fb0) already proved. Do not disable fbcon here:
	# olddefconfig would otherwise leave the panel on the green/yellow probe.
	"$KERNEL_SRC/scripts/config" --file "$KBUILD_OUTPUT/.config" \
		--enable FRAMEBUFFER_CONSOLE \
		--enable FRAMEBUFFER_CONSOLE_DETECT_PRIMARY \
		--enable FONTS --enable FONT_8x16 \
		--enable LOGO --enable LOGO_LINUX_CLUT224
	make O="$KBUILD_OUTPUT" olddefconfig
fi

echo "==> Building Image.gz + $DTB_NAME ($JOBS jobs)"
make O="$KBUILD_OUTPUT" -j"$JOBS" Image.gz dtbs modules

cp -f "$KBUILD_OUTPUT/arch/arm64/boot/Image.gz" "$OUT/Image.gz"
cp -f "$KBUILD_OUTPUT/arch/arm64/boot/dts/qcom/$DTB_NAME" "$OUT/$DTB_NAME"

echo "==> Installing modules for initramfs/overlay"
rm -rf "$OUT/modules"
make O="$KBUILD_OUTPUT" INSTALL_MOD_PATH="$OUT/modules" INSTALL_MOD_STRIP=1 modules_install

echo "==> Done"
ls -lh "$OUT/Image.gz" "$OUT/$DTB_NAME"
ls -ld "$OUT/modules/lib/modules/"* 2>/dev/null || true
