**语言：** [English](../device-inventory.md) | 简体中文

# 小米 5（gemini）设备盘点

记录时间：2026-08-27。当时设备在 TWRP 3.7.0_9-0，TWRP 救援环境。  
Ubuntu live dump 已采集：[`hardware-dump-ubuntu.md`](hardware-dump-ubuntu.md)，原始文件在 `inventory/2026-08-27-ubuntu/`。

## 1. 启动栈（不是 Android）

当前 `boot` 分区是 Android boot.img（header v0），里面是 Linux 主线系内核。`userdata` 整个就是 Ubuntu 根文件系统（label=`rootfs`）。

| 分区 | 块设备 | 内容 |
|------|--------|------|
| boot | sde36（64 MiB） | `6.1.14-umeko-rv0` + initrd |
| recovery | sde37（64 MiB） | TWRP 3.7.0_9-0 Omni `omni_gemini` |
| system | sda14（约 4.7 GiB） | 残留 LineageOS 17.1 / Android 10（2020-11-19），**不参与当前启动** |
| userdata | sda15（约 50 GiB） | Ubuntu 20.04.6 LTS，已用 12.4 GiB |
| modem | sde35 | 高通固件分区 |
| persist | sda12 | MAC、传感器校准等 |

boot 命令行：

```text
console=tty0 root=/dev/disk/by-partlabel/userdata rw loglevel=3 maxcpus=4
```

LK 追加的 Android 参数（TWRP `/proc/cmdline` 完整版）：

```text
androidboot.bootdevice=624000.ufshc
androidboot.verifiedbootstate=orange
androidboot.serialno=（省略）
androidboot.secureboot=1
androidboot.hwversion=1.4.0
androidboot.baseband=msm
mdss_mdp.panel=1:dsi:0:qcom,mdss_dsi_jdi_fhd_r63452_cmd:1:none:cfg:single_dsi
```

boot.img 头部：`ANDROID!` v0，`kernel_addr=0x80008000`，`page_size=4096`。

## 2. 硬件

| 项目 | 值 | 来源 |
|------|------|------|
| 机型 | Xiaomi Mi 5 / `gemini` | build.prop、DTS `xiaomi,gemini` |
| SoC | MSM8996（Snapdragon 820） | `/proc/cpuinfo` Hardware |
| CPU | 4× Kryo：2× 0x211 + 2× 0x205（implementer 0x51） | TWRP cpuinfo |
| 存储 | UFS `624000.ufshc` | androidboot.bootdevice |
| 面板 | JDI FHD R63452，command mode，single DSI | mdss_mdp.panel |
| GPU | Adreno 530 | 固件 `a530_zap.mbn` |
| 解锁 | orange / 已解锁 | verifiedbootstate |
| 硬件版本 | 1.4.0 | androidboot.hwversion |
| WLAN MAC | （省略） | persist |
| 电池设计容量 | 3000 mAh（上游 DTS） | msm8996-mainline gemini.dts |

CPU part：

- `0x211` = Kryo Silver（小核）
- `0x205` = Kryo Gold（大核）

maxcpus=4 与 4 核拓扑一致。

## 3. 当前内核 6.1.14-umeko-rv0

- 完整版本串：`Linux version 6.1.14-umeko-rv0 (root@97df89c06e5c) (aarch64-linux-gnu-gcc 9.4.0) #2 SMP PREEMPT Tue May 7 15:24:16 CST 2024`
- 包：`linux-image-6.1.14-umeko-rv0`
- 文件：`/boot/vmlinuz-6.1.14-umeko-rv0`、`config-…`、`System.map-…`、`initrd.img-…`
- 模块：572 个，路径 `/lib/modules/6.1.14-umeko-rv0`
- 配置副本：[`inventory/2026-08-27-twrp/config-6.1.14-umeko-rv0`](../../inventory/2026-08-27-twrp/config-6.1.14-umeko-rv0)

关键配置：

- `CONFIG_ARCH_QCOM`、`PINCTRL_MSM8996`、`MSM_GCC_8996`、`INTERCONNECT_QCOM_MSM8996`
- `DRM_MSM=m`、`DRM_PANEL_JDI_R63452=m`
- `SCSI_UFS_QCOM=y`
- `USB_DWC3` + `USB_CONFIGFS_SERIAL/ECM/RNDIS`
- `ATH10K_PCI=m`，**`ATH10K_SNOC` 未开**
- `ARM64_VA_BITS=48`（这台机能用 48-bit VA 启动）
- 触控：config 里开了 Atmel MXT，**真机是 Synaptics S3330 / rmi4**（与上游 DTS 一致）

`/etc/modprobe.d/touchscreens-workaround.conf` 显示实际依赖链：

```text
softdep drm pre: panel_jdi_fhd_r63452
softdep ath10k_pci pre: cfg80211
```

内核侧已经是 MSM DRM：`card0-DSI-1` 1080×1920、`msmdrmfb`。Xorg 配置仍写 `simplefb` 且 glamor 关闭，用户态没有完整 GPU 加速。

上次 Ubuntu 开机：Xorg 日志 `2025-12-14`。

## 4. 用户空间

- 发行版：Ubuntu 20.04.6 LTS (Focal)
- 主机名：`XiaoMi5-Ubuntu`
- 用户：`umeko`（sudo 全权限；passwd GECOS 写着 `redmi2`，镜像可能从别的机移植）
- SSH：已启用，UFW 放行 22
- USB：`autottyGS0.service` 在 gadget 串口上 `login -f umeko`（主机侧 `/dev/ttyACM0`）
- 用途：Klipper / Moonraker / Fluidd / KlipperScreen、1Panel、Docker/containerd，当作 3D 打印机主机

Wi-Fi NetworkManager 配置（SSID 与局域网地址已省略）：

| 连接 | 接口痕迹 |
|------|----------|
| 家庭 5 GHz 网络 | `wlp1s0`（PCI ath10k） |
| 另一条已保存网络 | `wlan0` |

## 5. 机上固件

`/lib/firmware/qcom/msm8996/gemini/`：

- `a530_zap.{b00,b01,b02,mbn,mdt}`
- `mba.mbn`、`modem.mbn`（约 51 MiB）、`slpi.mbn`、`venus.mbn`

另外有 `ath10k/WCN3990`。缺 `adsp.mbn` 的话 ADSP PIL 会失败（上游 DTS 需要它）。

## 6. 连接方式

| 模式 | 表现 |
|------|------|
| Ubuntu 运行中 | USB gadget CDC ACM，`0525:a4a7`，`Linux 6.1.14-umeko-rv0 with dwc3-gadget` |
| TWRP | 标准 ADB，`2717:ff68` Xiaomi MI 5，`recovery` |
| 本仓库已做 | 写入本机 ed25519 公钥到 root/umeko；开机 oneshot 采集 `/root/hw-dump/` |

## 7. 残留 Android

`system` 仍是 LineageOS 17.1（`lineage_gemini-userdebug`，Android 10 / SDK 29）。vendor 在 `cust`。不参与 Ubuntu 启动，但 TWRP 备份/还原时不要误伤，除非明确要擦 Android。
