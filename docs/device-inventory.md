**Language:** English | [简体中文](zh-CN/device-inventory.md)

# Xiaomi Mi 5 (gemini) inventory

Recorded 2026-08-27 from TWRP. Device serial, WLAN MAC, and filesystem UUID are omitted from the public tree.

Not Android at runtime: `boot` is a mainline-style Linux image; `userdata` is the Ubuntu root. `system` still has LineageOS 17.1 and is unused.

| Part | Block (typical) | Contents |
|------|-----------------|----------|
| boot | sde36 (64 MiB) | Linux + initrd |
| recovery | sde37 (64 MiB) | TWRP 3.7.0_9-0 |
| system | sda14 | Leftover LineageOS 17.1 |
| userdata | sda15 | Ubuntu root |
| modem | sde35 | Qualcomm firmware |
| persist | sda12 | MAC / calibration |

SoC MSM8996 (Kryo 2+2), UFS `624000.ufshc`, panel JDI FHD R63452 command mode, GPU Adreno 530, Wi-Fi QCA6174 PCI. Touch is Synaptics S3330 / rmi4, not Atmel.

Previous live kernel was `6.1.14-umeko-rv0` (msm8996-mainline family). USB gadget CDC ACM `0525:a4a7`.
