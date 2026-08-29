**Language:** English | [简体中文](zh-CN/flash-guide.md)

# Flash guide (Xiaomi Mi 5 / gemini)

This is for **Xiaomi Mi 5 only** (codename **gemini**, MSM8996). Do not flash these images on another phone. Do not flash [ginkgo](https://github.com/Huabin1010/ginkgo-mainline-linux) `dtbo` or `vbmeta` here.

You need an **unlocked bootloader**. Flashing **userdata** erases Android and everything on that partition.

Mi 5 uses **LK**, not ABL. The device tree is inside `boot.img`. There is **no** `dtbo-empty.img` step.

## What to download

A GitHub [Release](https://github.com/Huabin1010/gemini-mainline-linux/releases) ships the flashable images:

| Asset | Flash to | Notes |
|-------|----------|--------|
| `boot.img` | `boot` | Linux 7.0 + DTB + initramfs overlay (HUD) |
| `rootfs.ext4.zst` | `userdata` after decompress | GitHub rejects a raw 2 GiB `rootfs.ext4`; unpack first. **Wipes userdata.** |
| `SHA256SUMS` | — | Check the files before flashing |

The Release rootfs is a **minimal Ubuntu 26.04** image, not a full GNOME desktop. After first boot run `passwd`. You can build a newer image locally with `scripts/build-rootfs.sh`.

Keep your own backup of the previous `boot.img` (TWRP dump). Those files are gitignored.

First install: decompress the rootfs, flash userdata, then flash `boot`. Later kernel updates are **boot only**.

## Host tools

```bash
sudo apt install android-sdk-platform-tools zstd   # adb, fastboot, zstd
# or:  export PATH="$HOME/.local/bin:$PATH"
```

Unlock check:

```bash
fastboot devices
fastboot getvar unlocked          # should be yes
fastboot getvar product           # must be gemini
```

If `product` is not `gemini`, stop.

Enter LK: power off, then **Volume Down + Power**, or short **Volume Up** on the HUD. Success is USB **`18d1:d00d`**. A black panel or the word FASTBOOT on a USB ACM gadget (`0525:a4a7`) is **not** LK.

## First install (wipes userdata)

Download the Release assets (example tag `v0.1.0`):

```bash
gh release download v0.1.0 --repo Huabin1010/gemini-mainline-linux --dir out
# or the browser: https://github.com/Huabin1010/gemini-mainline-linux/releases
cd out && sha256sum -c SHA256SUMS
zstd -d -f rootfs.ext4.zst          # → rootfs.ext4 (2 GiB)
```

Or build the rootfs on the PC yourself:

```bash
git clone https://github.com/Huabin1010/gemini-mainline-linux.git
cd gemini-mainline-linux
./scripts/setup-deps.sh
cp rootfs-overlay/etc/gemini-root-password.example rootfs-overlay/etc/gemini-root-password
# edit that file, then:
chmod 600 rootfs-overlay/etc/gemini-root-password
./scripts/build-rootfs.sh
./scripts/configure-rootfs.sh
./scripts/build-rootfs-image.sh
```

Then:

```bash
export PATH="$HOME/.local/bin:$PATH"

# 1. Ubuntu → userdata  (ERASES this partition)
fastboot flash userdata out/rootfs.ext4

# 2. Mainline kernel + HUD
fastboot flash boot out/boot.img

fastboot reboot
```

## Kernel-only update (keep Ubuntu)

The phone already runs this rootfs; you only want a new kernel or HUD:

```bash
fastboot flash boot boot.img
fastboot reboot
```

Do **not** flash userdata again unless you intend to wipe.

From Ubuntu you can reboot to LK with short Volume Up on the HUD, or `reboot-fastboot`, then flash from the PC.

Hot-replace without flashing: `systemctl stop display-unblank.service`, copy a new `gemini-status` and `gemini-wifi-connect.sh` to `/usr/local/sbin/`, start the service. A reboot restores the copies from the initramfs overlay until you flash a new `boot.img`.

## After boot

USB serial: host `/dev/ttyACM0`, gadget `0525:a4a7`. The Release rootfs locks password hashes; USB serial autologin still reaches a shell. Run `passwd` before using SSH with a password.

SSH may be on USB RNDIS (`root@192.168.7.2`) or on Wi-Fi if you join a network from the HUD. The root password is **not** in this repo.

## Restore a previous kernel

You need the `boot.img` you saved **before** flashing Linux. Example from this tree (file is gitignored):

```bash
fastboot flash boot inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img
fastboot reboot
```

If userdata already holds Ubuntu, wiping it is a separate decision (`fastboot flash userdata` or TWRP).

## Do not

- Flash these images on a non-gemini device
- Flash ginkgo `dtbo` / `vbmeta` onto gemini
- Put passwords in a public Release
- Re-flash userdata just to update the HUD
- Type `reboot-fastboot` into the USB serial console (it races getty)

## Publish a Release (maintainers)

```bash
gh auth login          # once; git SSH is not enough for the API
./scripts/build-bootimg.sh
./scripts/publish-release.sh v0.1.0
```

The script uploads `out/boot.img` and `SHA256SUMS`. Rootfs is included only if `out/rootfs-release.ext4` exists (from `scripts/sanitize-rootfs-for-release.sh`). It compresses that copy to `rootfs.ext4.zst`. It does **not** upload the live `out/rootfs.ext4` or any dtbo.
