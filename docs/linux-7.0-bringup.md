**Language:** English | [简体中文](zh-CN/linux-7.0-bringup.md)

# First Linux 7.0 boot on gemini

2026-08-27. Xiaomi Mi 5 (**gemini**, MSM8996). `fastboot boot` reached Ubuntu with kernel `7.0.0-umeko-rv0-dirty`, USB ACM auto-login, DRM on `msmdrmfb`. The 6.1 boot partition was **not** overwritten on that first attempt.

`--base` must be `0x80000000`. A 7.0 `Image` is larger than umeko's 16 MiB kernel-to-ramdisk gap; ramdisk is at `0x84000000`. USB ACM is kernel `g_serial` (`0525:a4a7`); do not bind a second configfs gadget on the same UDC. ADSP PIL firmware can stall boot; it stays disabled/modular like umeko.

Rescue 6.1 image (gitignored): `inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img`.
