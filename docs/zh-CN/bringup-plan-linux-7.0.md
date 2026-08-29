**语言：** [English](../bringup-plan-linux-7.0.md) | 简体中文

# Linux 7.0 适配计划（gemini）

基线：现网 Ubuntu 20.04 + `6.1.14-umeko-rv0`。  
目标内核：torvalds **v7.0** + 上游 `msm8996-xiaomi-gemini.dts`。  
策略：**只换 boot 分区**，继续用 userdata 上的 Ubuntu。TWRP 留着当救援。

## 原则

1. 不先刷 7.0 覆盖唯一能用的 6.1 boot。先 `fastboot boot` 或备份 boot 再 `dd`。
2. 7.0 第一刀必须保住：UFS 挂上 userdata、USB gadget 串口、能看到 dmesg。
3. 显示/触控/Wi-Fi 分阶段，对照 live dump，不要按 DTS 臆测。
4. 从 msm8996-mainline 6.19/staging 只挑 7.0 里还没有、且这台机需要的补丁。

## 阶段

### P0 盘点（本轮）

- [x] TWRP 下记录分区、内核、固件、命令行
- [x] 对照主线 DTS / msm8996-mainline / postmarketOS
- [x] 仓库脚本 + `config/gemini.fragment`
- [x] Ubuntu 里跑 dump（串口拉回 `inventory/2026-08-27-ubuntu/`）
- [x] 触控 Synaptics S3330；Wi-Fi QCA6174 PCI；DRM DSI 1080×1920

### P1 编译 7.0

```bash
./scripts/setup-deps.sh
./scripts/setup-kernel.sh    # clone v7.0
./scripts/build-kernel.sh    # Image.gz + msm8996-xiaomi-gemini.dtb
./scripts/build-bootimg.sh
```

检查：

- `dtbs_check` 或至少 `dtc` 编出 DTB
- `.config` 里 `SCSI_UFS_QCOM=y`、`USB_CONFIGFS_SERIAL=y`、`DRM_PANEL_JDI_R63452`
- 备份当前 boot：`adb pull` 或 TWRP 备份

### P2 第一次启动

**已完成（2026-08-27）**：`fastboot boot` 进入 Ubuntu 20.04.6，`uname` 为 `7.0.0-umeko-rv0-dirty`，USB `g_serial` 自动登录。过程、根因和遗留问题见 [`linux-7.0-bringup.md`](linux-7.0-bringup.md)。分区上的 6.1 boot **没有**被覆盖。

期望 cmdline（`scripts/build-bootimg.sh`）：

```text
console=tty0 ignore_loglevel loglevel=8 clk_ignore_unused pd_ignore_unused root=/dev/disk/by-partlabel/userdata rootwait rw maxcpus=4 panic=10
```

成功判据：

- 主机再枚举 gadget 串口或 SSH
- `uname -r` 为 `7.0.0` 一类
- `root=` UUID 挂上，systemd 起来

失败就进 TWRP 把备份 boot 写回去。

### P3 显示

**部分完成**：7.0 已 `[drm] Initialized msm`、`fb0: msmdrmfb`。`msm_mdp` 必须绑上 GPU 才会出 fb；关掉 GPU 会永远停在 LK splash。zap 固件仍 `error -5`（initramfs 里是 APQ8096 通用包，不是机上 gemini 那份）。

上游面板 `jdi,fhd-r63452` 与 LK 的 `mdss_dsi_jdi_fhd_r63452_cmd` 一致。7.0 走 `DRM_MSM`，fbcon 打到 `tty0`。

若黑屏但串口活着：抓 dmesg 里 `msm`/`dsi`/`r63452`/`panel init`。

### P4 触控

live dump 已确认 **Synaptics S3330**（`rmi4` i2c `2-0020`）。fragment 开 RMI4，不再开 Atmel MXT。

### P5 Wi-Fi

live dump 确认是 **PCIe QCA6174 hw3.2**（`ath10k_pci` → `wlp1s0`），不是 WCN3990 SNOC。7.0 fragment 只开 PCI。需要 `ath10k/QCA6174/hw3.0` 固件。

### P6 GPU

机上已有 `a530_zap.mbn`。现网 Xorg simplefb + 无 glamor。7.0 先保证 KMS，再开 glamor/freedreno。

## 不在第一刀里的东西

- 不重做 rootfs（已有 Ubuntu 20.04 + Klipper）
- 不碰 `system` 里的 LineageOS
- 不刷 aboot/xbl
- 不把 51 MiB `modem.mbn` 提交进 git

## 救援

6.1 备份：`inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img`

```bash
fastboot flash boot inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img
fastboot reboot
```

`mkbootimg --base` 必须是 `0x80000000`（umeko 是 `kernel@0x80008000`）。写成 `0x0` 会把内核加载到 `0x8000`，LK 一跳就卡死。

7.0 `Image` 约 42 MiB，不能再用 umeko 的 `ramdisk@0x81000000`（距内核只有 16 MiB），解压会盖掉 ramdisk。当前用 `ramdisk@0x84000000`。
