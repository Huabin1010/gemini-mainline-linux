#!/usr/bin/env bash
# Pack Android boot.img v0 for Xiaomi Mi 5 (gemini / MSM8996).
# Header must match working umeko 6.1: ANDROID! v0, kernel@0x80008000.
# MSM8996 LK DRAM starts at 0x80000000. --base 0x0 loads the kernel at
# 0x8000 (not RAM) and the phone hangs with USB gone.
#
# Uncompressed 7.0 Image is ~42 MiB. umeko used ramdisk@0x81000000 (16 MiB
# after kernel), which the 7.0 Image overwrites by ~26 MiB during gunzip.
# Put ramdisk at +64 MiB so decompress cannot clobber it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/env.sh
source "$ROOT/scripts/env.sh"

OUT="$ROOT/out"
KERNEL="$OUT/Image.gz"
DTB="$OUT/$DTB_NAME"
BOOTIMG="${BOOTIMG:-$OUT/boot.img}"
RAMDISK="${RAMDISK:-$OUT/initramfs.cpio.gz}"
IMAGE="${IMAGE:-$KBUILD_OUTPUT/arch/arm64/boot/Image}"

KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x04000000
SECOND_OFFSET=0x04f00000
TAGS_OFFSET=0x00000100

# Last console= wins as /dev/console. tty0 last → fbcon is the panel console
# (ginkgo same trick). ttyGS0 still gets a printk copy on USB ACM.
# Do not use earlycon at 0x7570000 (BT UART). GDM stays masked.
CMDLINE="${CMDLINE:-console=ttyGS0,115200 console=tty0 ignore_loglevel loglevel=8 clk_ignore_unused pd_ignore_unused root=/dev/disk/by-partlabel/userdata rootwait rw maxcpus=4}"

[[ -f "$KERNEL" ]] || { echo "missing $KERNEL — run scripts/build-kernel.sh first" >&2; exit 1; }
[[ -f "$DTB" ]] || { echo "missing $DTB — run scripts/build-kernel.sh first" >&2; exit 1; }

if [[ -f "$IMAGE" ]]; then
	img_size=$(stat -c%s "$IMAGE")
	gap=$((RAMDISK_OFFSET - KERNEL_OFFSET))
	if (( img_size >= gap )); then
		echo "error: uncompressed Image ${img_size} >= ramdisk gap ${gap}; raise RAMDISK_OFFSET" >&2
		exit 1
	fi
	echo "    Image ${img_size} bytes, ramdisk gap ${gap} (ok)"
fi

"$ROOT/scripts/build-initramfs.sh"
[[ -f "$RAMDISK" ]] || { echo "missing $RAMDISK" >&2; exit 1; }

mkdir -p "$OUT"
cat "$KERNEL" "$DTB" > "$OUT/Image.gz-dtb"

MKBOOTIMG="$(command -v mkbootimg || true)"
[[ -n "$MKBOOTIMG" ]] || { echo "mkbootimg not found; run scripts/setup-deps.sh" >&2; exit 1; }

echo "==> Packing $(basename "$BOOTIMG")"
"$MKBOOTIMG" \
	--kernel "$OUT/Image.gz-dtb" \
	--ramdisk "$RAMDISK" \
	--cmdline "$CMDLINE" \
	--pagesize 4096 \
	--base 0x80000000 \
	--kernel_offset "$KERNEL_OFFSET" \
	--ramdisk_offset "$RAMDISK_OFFSET" \
	--second_offset "$SECOND_OFFSET" \
	--tags_offset "$TAGS_OFFSET" \
	-o "$BOOTIMG"

python3 - "$BOOTIMG" <<'PY'
import struct, sys
p = sys.argv[1]
d = open(p, "rb").read(48)
magic, ksize, kaddr, rsize, raddr, ssize, saddr, tags, pagesize = struct.unpack_from("<8s8I", d)
assert magic == b"ANDROID!", magic
assert kaddr == 0x80008000, hex(kaddr)
assert raddr == 0x84000000, hex(raddr)
assert tags == 0x80000100, hex(tags)
assert pagesize == 4096, pagesize
print(f"    header OK  kernel@0x{kaddr:08x} ramdisk@0x{raddr:08x} tags@0x{tags:08x} k={ksize} r={rsize}")
PY

ls -lh "$BOOTIMG"
echo "Try without flashing:  fastboot boot $BOOTIMG"
echo "Flash:                 ./scripts/flash-boot.sh"
echo "6.1 backup:            inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img"
