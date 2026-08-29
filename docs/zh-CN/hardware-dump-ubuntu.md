**语言：** [English](../hardware-dump-ubuntu.md) | 简体中文

# Ubuntu live 硬件 dump（2026-08-27）

设备已从 TWRP 重启回 Ubuntu。主机枚举 CDC ACM `/dev/ttyACM0`。RTC 停在 2025-12-14（上次正常关机时间），dump 时间戳因此是 `20251214-104644`。

原始文件：[`inventory/2026-08-27-ubuntu/hw-dump/`](../../inventory/2026-08-27-ubuntu/hw-dump/)。

## 已确认

| 项目 | 实测 |
|------|------|
| 内核 | `6.1.14-umeko-rv0` #1 SMP PREEMPT 2024-05-07 |
| DT model | `Xiaomi Mi 5` |
| compatible | `xiaomi,gemini` `qcom,msm8996` |
| 内存 | MemTotal 2763876 kB（约 3 GB 机） |
| 根分区 | UFS `sda15` label=`rootfs` UUID 随重装变化 |
| 显示 | DRM `card0-DSI-1` **connected**，模式 **1080×1920**，`msmdrmfb` |
| GPU | Adreno `b00000.gpu`，已加载 `a530_pm4.fw` / `a530_pfp.fw` / `a530v3_gpmu.fw2` |
| 触控 | **Synaptics S3330**（rmi4，i2c `2-0020`），fw id 2613032 |
| 按键 | `pm8941_pwrkey`、`pm8941_resin`、`gpio-keys` |
| 马达 | `drv260x` i2c `1-005a` |
| 电池 | `qcom-battery` 98%，设计 3000 mAh，4.354 V，Li-ion，USB SDP |
| Wi-Fi | **ath10k_pci QCA6174 hw3.2** `0000:01:00.0` → `wlp1s0`（接口 DOWN；MAC 已省略） |
| USB | gadget 串口；没有 usb0/RNDIS 地址 |

I2C 设备：`0-0028`、`1-0030`（lp5562 按键灯，probe -22）、`1-0047`、`1-005a`、`2-0020`。

## dmesg 里需要 7.0 继续盯的问题

- `qcom/msm8996/gemini/adsp.mbn` 缺失，ADSP remoteproc 失败
- `qcom_rmtfs_mem` assign memory -22
- `rmi4_i2c`：`supply vio not found, using dummy regulator`（触控仍工作）
- `lp5562` probe -22
- `qcom,wled` IRQ ovp -ENXIO
- `adreno` vdd/vddcx dummy regulator
- PSCI `failed to set PC mode: -1`（早期，仍启动成功）

## 对 7.0 的直接含义

1. 上游 `msm8996-xiaomi-gemini.dts` 和现网 DT compatible/面板/触控一致，7.0 应直接用这份 DTS。
2. Wi-Fi **不要**按 WCN3990/SNOC 配，应按 **QCA6174 + ATH10K_PCI**。
3. 显示已经是 MSM DRM + JDI R63452，不是纯 simplefb。
4. 缺 `adsp.mbn` 是固件问题，不是 DTS 问题。
