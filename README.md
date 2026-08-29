# gemini-mainline-linux

**Language:** English | [简体中文](README.zh-CN.md)

Mainline Linux bring-up for **Xiaomi Mi 5** (codename **gemini**, Qualcomm **MSM8996 / Snapdragon 820**).

This tree builds Linux 7.0 + an Ubuntu 26.04 arm64 rootfs and flashes them onto the phone. It is **not** AOSP. `system` still holds leftover LineageOS 17.1; boot does not use Android userspace. Ubuntu lives on **userdata**. Day-to-day kernel updates are **boot only**.

On the tester unit: GLES HUD (Wi-Fi, backlight, language, CPU/GPU/RAM, up/down rates), GDM kept masked so gnome-shell does not black the scanout.

| Stage | Goal | Status |
|-------|------|--------|
| P0 | Device inventory + upstream research | Done |
| P1 | Linux 7.0 + `boot.img` | Done |
| P2 | UFS rootfs + USB serial | Done (`g_serial` ACM `0525:a4a7`) |
| P3 | DRM / JDI R63452 display | Done (XRGB8888 fbdev; HUD owns the panel) |
| P4 | Touch (Synaptics S3330) | HUD tap/drag works |
| P5 | Wi-Fi (QCA6174 / `ath10k_pci`) | HUD scan + NetworkManager |
| P6 | GPU Adreno 530 | GLES 3.1 / freedreno FD530; HUD prefers GBM/GLES2 |
| P7 | GNOME | Overlay present; GDM masked (it blacks MSM scanout) |
| P8 | Reboot to LK from the OS | Short **Volume Up** on the HUD → USB `18d1:d00d` |

**Flash a Release image:** [English](docs/flash-guide.md) · [中文](docs/zh-CN/flash-guide.md)

Hardware notes and the bring-up story live under [`docs/`](docs/README.md). Chinese originals are in [`docs/zh-CN/`](docs/zh-CN/README.md).

## This is not ginkgo

The sibling tree [ginkgo-mainline-linux](https://github.com/Huabin1010/ginkgo-mainline-linux) is Redmi Note 8 (SM6125, ABL). **Do not** flash ginkgo `dtbo` / `vbmeta` onto gemini. Mi 5 boots **LK**; the DTB is packed inside `boot.img`. There is no empty-dtbo step.

## Quick start

```bash
# 1. Host packages (once, needs sudo)
./scripts/setup-deps.sh

# 2. Fetch kernel sources (once)
./scripts/setup-kernel.sh

# 3. Build kernel + gemini DTB
./scripts/build-kernel.sh

# 4. Pack boot.img
./scripts/build-bootimg.sh

# 5. Build Ubuntu rootfs (first install only)
./scripts/build-rootfs.sh
./scripts/configure-rootfs.sh
./scripts/build-rootfs-image.sh

# 6. Flash (device in LK fastboot, USB 18d1:d00d)
./scripts/flash-boot.sh
# First install only — this wipes userdata:
# fastboot flash userdata out/rootfs.ext4
```

Kernel sources (`linux/`) and build outputs (`out/`) are not in git.

## Flash order

**First install** (wipes userdata):

```bash
export PATH="$HOME/.local/bin:$PATH"
fastboot getvar product          # must be gemini
zstd -d -f rootfs.ext4.zst       # if you downloaded a Release
fastboot flash userdata out/rootfs.ext4
fastboot flash boot out/boot.img
fastboot reboot
```

**Kernel-only update** (keep Ubuntu):

```bash
fastboot flash boot out/boot.img
fastboot reboot
```

Do **not** flash userdata again unless you intend to wipe.

Login: USB ACM (`0525:a4a7`) or SSH. The root password is **not** in this repo. Put it in the gitignored file `rootfs-overlay/etc/gemini-root-password` (see the `.example` file), or export `GEMINI_ROOT_PASSWORD`.

Enter LK: power off, then **Volume Down + Power**. From the HUD: short **Volume Up** only (do not hold Power at the same time).

## Layout

```
config/           Kernel config fragment
scripts/          Build, flash, and host helpers
docs/             English technical notes
docs/zh-CN/       Chinese originals
firmware/gemini/  Device-extracted firmware (blobs gitignored)
overlays/         Local DTS / fuel-gauge bits included at build time
rootfs-overlay/   Files copied into the Ubuntu image and initramfs overlay
initramfs/        Static /init + GLES HUD
tests/            Host unit tests for the Wi-Fi join flow
inventory/        Partition notes (images gitignored)
```

## Documentation

| Topic | English | 中文 |
|-------|---------|------|
| Flash a Release | [flash guide](docs/flash-guide.md) | [刷机教程](docs/zh-CN/flash-guide.md) |
| Doc index | [docs/README.md](docs/README.md) | [docs/zh-CN/README.md](docs/zh-CN/README.md) |
| What runs on the phone | [what we built](docs/what-we-built.md) | [中文](docs/zh-CN/what-we-built.md) |
| First 7.0 boot | [bring-up log](docs/linux-7.0-bringup.md) | [中文](docs/zh-CN/linux-7.0-bringup.md) |
| Display + reboot-fastboot | [2026-08-28](docs/display-and-reboot-fastboot-7.0.md) | [中文](docs/zh-CN/display-and-reboot-fastboot-7.0.md) |
| HUD worklog | [2026-08-29](docs/worklog-2026-08-29.md) | [中文](docs/zh-CN/worklog-2026-08-29.md) |

## Environment

See `scripts/env.sh`:

| Variable | Default | Meaning |
|----------|---------|---------|
| `KERNEL_TAG` | v7.0 | Kernel version |
| `KBUILD_OUTPUT` | `out/kernel` | Build tree |
| `GEMINI_ROOT_PASSWORD` | *(unset)* | Root password for the image; otherwise read from the overlay file |

## License

Build scripts and original documentation in this repository are [GPL-2.0-only](LICENSE), same as the Linux kernel. Device firmware blobs are proprietary; they are provided only for running Linux on the device they were extracted from.
