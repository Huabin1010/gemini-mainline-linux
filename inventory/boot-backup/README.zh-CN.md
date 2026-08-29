# 能用的 6.1 boot 备份

**语言：** [English](README.md) | 简体中文

- 文件：`boot-umeko-6.1.14-from-twrp.img`（64 MiB，整分区）。gitignore。
- SHA256：`9871a481dab9172411464ebdc7f35eb6ee404abbf84fd62e6b969e8c836c1ef9`
- 来源：2026-08-27 TWRP `dd` `/dev/block/bootdevice/by-name/boot`
- 内容：`6.1.14-umeko-rv0`，load `kernel@0x80008000`

7.0 ram-boot 快照（**不要** flash 覆盖 6.1，除非你打算换掉）：

- **可用：** `boot-7.0-noimem.img`（无 pshold、无 IMEM；reboot-fastboot 走 misc BCB）
- **可用：** `boot-7.0-nopshold.img`（无 pshold；内核 `#6`）
- **不要启动：** `boot-7.0-imem-reboot.img`（开机映射 IMEM，会卡死）

试启动：`fastboot boot inventory/boot-backup/boot-7.0-noimem.img`

这台机的 LK **不支持** `fastboot fetch`。再备份一次请进 TWRP：

```bash
adb pull /dev/block/bootdevice/by-name/boot inventory/boot-backup/boot-$(date +%F).img
```

刷回去（fastboot）：

```bash
fastboot flash boot inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img
fastboot reboot
```
