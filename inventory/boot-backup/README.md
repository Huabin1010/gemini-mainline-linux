# Usable 6.1 boot backup

**Language:** English | [简体中文](README.zh-CN.md)

- File: `boot-umeko-6.1.14-from-twrp.img` (64 MiB, whole partition). Gitignored.
- SHA256: `9871a481dab9172411464ebdc7f35eb6ee404abbf84fd62e6b969e8c836c1ef9`
- Source: 2026-08-27 TWRP `dd` of `/dev/block/bootdevice/by-name/boot`
- Contents: `6.1.14-umeko-rv0`, load `kernel@0x80008000`

7.0 ram-boot snapshots (**do not** flash over the 6.1 backup unless you intend to):

- **OK to boot:** `boot-7.0-noimem.img` (no pshold, no IMEM; reboot-fastboot uses misc BCB)
- **OK to boot:** `boot-7.0-nopshold.img` (no pshold; kernel `#6`)
- **Do not boot:** `boot-7.0-imem-reboot.img` (maps IMEM at boot and hangs)

Try without flashing: `fastboot boot inventory/boot-backup/boot-7.0-noimem.img`

This phone's LK does **not** support `fastboot fetch`. To dump again, use TWRP:

```bash
adb pull /dev/block/bootdevice/by-name/boot inventory/boot-backup/boot-$(date +%F).img
```

Restore (fastboot):

```bash
fastboot flash boot inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img
fastboot reboot
```
