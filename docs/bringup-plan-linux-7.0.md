**Language:** English | [简体中文](zh-CN/bringup-plan-linux-7.0.md)

# Linux 7.0 bring-up plan

Baseline was Ubuntu on userdata + umeko 6.1. Match the ginkgo method: mainline sources, device fragment, DTS overlay, UFS initramfs, USB gadget, **boot-only** daily flashes.

P0–P8 status is in the root [README](../README.md). First successful boot: [linux-7.0-bringup.md](linux-7.0-bringup.md). Rescue 6.1 `boot.img` is gitignored under `inventory/boot-backup/`.
