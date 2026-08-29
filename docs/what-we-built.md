**Language:** English | [简体中文](zh-CN/what-we-built.md)

# Xiaomi Mi 5 mainline Linux 7.0: what runs, how it is wired

Recorded 2026-08-28, updated 2026-08-29. Device: Xiaomi Mi 5 (**gemini**, MSM8996 / Snapdragon 820). Serial numbers and LAN addresses are omitted.

This is the bring-up line from a live 6.1 Ubuntu install to Linux 7.0, then a framebuffer HUD (Wi-Fi, backlight, language, CPU/GPU/RAM). Failure timelines: [linux-7.0-bringup.md](linux-7.0-bringup.md). Display and Volume-Up fastboot: [display-and-reboot-fastboot-7.0.md](display-and-reboot-fastboot-7.0.md).

## 1. Current stack

This is **not** AOSP.

| Partition | Contents |
|-----------|----------|
| `boot` | Android boot.img v0: **Linux 7.0** + initramfs overlay |
| `userdata` (UFS `sda15`) | **Ubuntu 26.04** (do not re-flash unless you mean to wipe) |
| `recovery` | TWRP 3.7.0_9-0 |
| `system` | Leftover LineageOS 17.1, unused at boot |

The panel shows a self-drawn **HUD** (`gemini-status`). GDM / gdm3 / display-manager / `getty@tty1` stay masked. Wi-Fi is PCIe **QCA6174** (`ath10k_pci` → `wlp1s0`) via NetworkManager. USB in the OS is kernel **`g_serial`**: `0525:a4a7`. LK fastboot is `18d1:d00d`.

## 2. Stages

| Stage | What | Result |
|-------|------|--------|
| P0 | TWRP inventory + 6.1 live dump | Panel / touch / Wi-Fi / GPU identified |
| P1 | Linux 7.0 `Image.gz` + DTB + `boot.img` | `out/boot.img` |
| P2 | Initramfs mounts UFS + `g_serial` | 7.0 reaches Ubuntu |
| P3 | MSM DRM + JDI R63452 fbdev | `write(/dev/fb0)` visible; pixels **XRGB8888** |
| P4 | Synaptics S3330 | HUD tap/drag |
| P5 | QCA6174 Wi-Fi | HUD scan/join |
| P6 | Adreno 530 | MDP bound to GPU; GLES 3.1 / FD530; HUD prefers GBM/GLES2 |
| P7 | GNOME | Overlay ready; **GDM stays masked** |
| P8 | Reboot to LK | Short Volume Up on the HUD |

## 3. Tree

| Path | Role |
|------|------|
| `linux/` | Linux 7.0 sources (gitignored, fetched by script) |
| `config/gemini.fragment` | kconfig on top of arm64 defconfig |
| `overlays/` | Local DTS / fuel-gauge, `#include`d at the end of upstream DTS |
| `initramfs/init.c` | Static `/init`: find userdata, copy overlay, `switch_root` |
| `initramfs/gemini-status.c` | HUD |
| `rootfs-overlay/` | Copied onto userdata at boot (initramfs overlay) |
| `scripts/build-bootimg.sh` | `mkbootimg`: `Image.gz`+DTB + ramdisk |

`--base` must be `0x80000000` (kernel at `0x80008000`). `--base 0x0` loads the kernel at `0x8000` (not DRAM) and USB dies. Ramdisk is at **+64 MiB** so a 7.0 `Image` cannot overwrite it.

Root is `root=/dev/disk/by-partlabel/userdata` (filesystem UUID changes after a reformat).

## 4. HUD jobs

| kind | Command | Use |
|------|---------|-----|
| 0 | `nmcli radio wifi on` | Radio |
| 1 | `nmcli device` | Link state |
| 2 | `nmcli device wifi list` | Scan |
| 3 | `gemini-wifi-connect.sh` | Join |
| 4 | `iw dev IFACE link` | Live SSID / RSSI |
| 5 | `gemini-wifi-connect.sh forget` | Forget |

Only one job at a time. Join/forget abort an in-flight scan.

Ubuntu 26.04 on this image is **netplan + NetworkManager 1.54**. `nmcli connection up` does not use the keyfile PSK unless you also pass **`passwd-file`**. Do not use `nmcli device wifi connect` as the main path (it reuses a profile with no secret). Details: [worklog-2026-08-29.md](worklog-2026-08-29.md).

The HUD has no PolicyKit agent (`auth-polkit=false` in the overlay). Root password is not in git (`rootfs-overlay/etc/gemini-root-password`).

## 5. Do not

- Flash userdata unless you intend to wipe Ubuntu
- Flash ginkgo `dtbo` / `vbmeta` onto gemini
- Type `reboot-fastboot` into USB ACM (races getty)
- Unmask GDM while the HUD owns MSM scanout
