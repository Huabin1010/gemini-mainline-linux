**语言：** [English](../what-we-built.md) | 简体中文

# 小米 5 主线 Linux 7.0：做了什么、怎么实现

记录时间：2026-08-28。  
机器：Xiaomi Mi 5（代号 **gemini**，高通 **MSM8996 / Snapdragon 820**），硬件版本 `1.4.0`。  
仓库：本目录上一级。

本文写整条适配线：**从现网 6.1 Ubuntu 迁到 Linux 7.0，再到 framebuffer HUD（Wi-Fi / 亮度 / 中英 / CPU·GPU·内存）**。  
失败时间线、USB 卡死对照见 [`linux-7.0-bringup.md`](linux-7.0-bringup.md)；绿黄探针与音量+进 fastboot 见 [`display-and-reboot-fastboot-7.0.md`](display-and-reboot-fastboot-7.0.md)。本文侧重 **现在机器上实际在跑的栈** 和 **每一块是怎么接到一起的**。

---

## 1. 一句话现状

这台机 **不是** AOSP / Android Generic Kernel。`system` 分区里还留着 LineageOS 17.1，当前启动不走 Android。

| 分区 | 实际内容 |
|------|----------|
| `boot` | Android boot.img v0：**Linux 7.0.0-umeko-rv0-dirty** + initramfs overlay |
| `userdata`（UFS `sda15`） | **Ubuntu 26.04**（从 20.04 整盘换过一次；之后 **不再刷 userdata**） |
| `recovery` | TWRP 3.7.0_9-0 |
| `system` | 残留 LineageOS 17.1，不参与启动 |

开机后屏上是自绘 **HUD**（`gemini-status`），GDM / gdm3 / display-manager / `getty@tty1` 全部 mask。  
Wi-Fi 是 PCIe **QCA6174**（`ath10k_pci` → `wlp1s0`），经 NetworkManager 连接。  
USB 系统态是内核 **`g_serial`**：`0525:a4a7`；进 LK fastboot 是 `18d1:d00d`。

---

## 2. 目标与阶段

对齐旁边的 ginkgo（`Kernel-Build`）做法：主线源码 + 本机 fragment / DTS overlay + UFS initramfs + USB gadget，**日常只换 boot**，rootfs 留在 userdata。

| 阶段 | 做了什么 | 结果 |
|------|----------|------|
| P0 | TWRP 盘点 + 进 6.1 Ubuntu live dump + 上游对照 | 确认面板 / 触控 / Wi-Fi / GPU 真实型号 |
| P1 | 拉 Linux 7.0，编 `Image.gz` + DTB + `boot.img` | 产物在 `out/boot.img` |
| P2 | initramfs 挂 UFS + `g_serial` ACM | 7.0 进 Ubuntu，串口自动登录 |
| P3 | MSM DRM + JDI R63452 fbdev | `write(/dev/fb0)` 可见；像素 **XRGB8888** |
| P4 | Synaptics S3330 触控 | 点屏 / 滑卡片可用；未当桌面指针验 |
| P5 | QCA6174 Wi-Fi | HUD 能扫、能连、能显示 dBm/% |
| P6 | Adreno 530 | MDP 绑 GPU 才能出 `msmdrmfb`；**GLES 3.1 / FD530 已通**（vendor 签名 zap）；HUD 优先 GBM/GLES2 扫描 |
| P7 | GNOME | overlay 备好，**GDM 保持 mask**（会冲黑扫描） |
| P8 | 系统内进 LK | HUD 上 **只短按音量+**（不要按电源） |
| HUD | 状态屏：选网、背光、中英、每核 CPU、温度、降帧 | 当前默认界面 |

---

## 3. 仓库怎么摆

| 路径 | 作用 |
|------|------|
| `linux/` | Linux 7.0 源码（gitignored，本地拉取） |
| `config/gemini.fragment` | 叠在 arm64 defconfig 上的本机 kconfig |
| `overlays/linux/.../msm8996-xiaomi-gemini-local.dtsi` | 不改上游 DTS 正文，末尾 `#include` 本地补丁 |
| `initramfs/init.c` | 静态 `/init`：找 userdata、拷 overlay、`switch_root` |
| `initramfs/gemini-status.c` | HUD 本体（交叉编译进 overlay） |
| `initramfs/gemini-status-font.h` | 烘焙好的 Noto CJK 点阵 |
| `initramfs/reboot-bootloader.c` | `SYS_reboot(..., "bootloader")` |
| `rootfs-overlay/` | 每次开机由 initramfs 覆盖进 userdata |
| `scripts/build-kernel.sh` | 合并 fragment、编内核/模块 |
| `scripts/build-initramfs.sh` | 编 init + HUD + 打包 cpio |
| `scripts/build-bootimg.sh` | `mkbootimg`：`Image.gz`+DTB + ramdisk |
| `scripts/build-rootfs.sh` 等 | Ubuntu 26.04 rootfs 镜像（**只在换盘时用**） |
| `firmware/` / `inventory/` | 固件、6.1 dump、boot 备份 |
| `docs/zh-CN/` | 中文记录 |

构建入口：

```bash
./scripts/build-all.sh          # 内核 + initramfs + boot.img
./scripts/build-bootimg.sh      # 只改 HUD / overlay 时够用
```

只改 `gemini-status.c` 不必重编内核。改 `gemini.fragment` 或 MSM 驱动才跑 `build-kernel.sh`。

---

## 4. 启动链（从 LK 到 HUD）

```text
LK (fastboot / 正常开机)
  → 加载 ANDROID! boot.img
       kernel  @ 0x80008000   (base 0x80000000 + 0x8000)
       ramdisk @ 0x84000000   (+64 MiB，躲开 7.0 解压后的 Image)
  → Linux 7.0
  → initramfs /init
       等 UFS，按 UUID / label / sda15 挂 userdata
       把 ramdisk 里的 overlay/ 拷进根分区
       switch_root → systemd
  → display-unblank.service
       modprobe 面板 + msm + ath10k_pci
       等 /dev/fb0，按 hud.conf 设背光
       exec /usr/local/sbin/gemini-status
  → HUD 占屏：优先 GBM/EGL/GLES2，失败才 write(fb0)
```

boot 头必须是：

```text
ANDROID! v0  kernel@0x80008000  ramdisk@0x84000000  tags@0x80000100  pagesize=4096
```

`--base 0x0` 会把内核放到 `0x8000`（不是 DRAM），USB 立刻没。umeko 6.1 的 ramdisk 在 `0x81000000`（距内核 16 MiB），7.0 未压缩 Image 约 25 MiB+，会盖掉 ramdisk，所以 ramdisk 固定在 **+64 MiB**。`build-bootimg.sh` 打包后会 assert 这几个地址。

cmdline（`scripts/build-bootimg.sh`）：

```text
console=ttyGS0,115200 console=tty0 ignore_loglevel loglevel=8
clk_ignore_unused pd_ignore_unused
root=/dev/disk/by-partlabel/userdata rootwait rw maxcpus=4
```

不要 `earlycon` 打到 `0x7570000`（那是蓝牙 UART `blsp1_uart2`，会早死）。  
不要 `panic=10`、不要 `nowatchdog`。  
LK 仍会追加 Android 面板参数，可忽略。

initramfs 找根分区的顺序（`initramfs/init.c`）：

1. UUID 随重装变化（20.04 原 UUID；换 26.04 后可能变）
2. `label=rootfs` / `partlabel=userdata`
3. `/dev/sda15`

26.04 的 fstab 用 `/dev/disk/by-partlabel/userdata`，避免 UUID 刷盘后对不上。

---

## 5. 内核与设备树：为了能起来改了什么

### 5.1 fragment（`config/gemini.fragment`）

对照 6.1.14-umeko-rv0 的 `.config` 和 2026-08-27 live dump，叠在 `defconfig` 上。要点：

| 项 | 取值 | 原因 |
|----|------|------|
| `ARM64_VA_BITS=48` | 必须 | defconfig 是 52-bit，Kryo 起不来 |
| `CONFIG_EFI` | 关 | LK 不是 EFI；stub/earlycon 会卡在 USB 之前 |
| `USB_G_SERIAL=y` | 内建 | 6.1 就是它出 `0525:a4a7`；configfs ACM 会抢 UDC，ttyGS0 没数据 |
| `DRM_MSM=m` + 面板 `=m` | 模块 | 编进内核会跟 LK splash 抢，USB 有、ACM 空、屏停在 FASTBOOT 字 |
| `DRM_FBDEV_EMULATION=y` | 开 | 第一次 modeset + `/dev/fb0` |
| `ATH10K_PCI=y`，SNOC 关 | — | 真机是 PCIe QCA6174，不是 WCN3990 |
| `RMI4_I2C` | 开 | 触控是 Synaptics S3330 @ i2c-2 `0x20`，不是 Atmel |
| `ARM_PSCI_CPUIDLE=y` | 开 | 没有它 sysfs 无 cpuidle，核不进 WFI/cpu-sleep，HUD 空闲也烫 |
| `POWER_RESET_QCOM_PON` | 开 | `reboot bootloader` 走 pm8994 PON |
| `POWER_RESET_QCOM_IMEM` | 关 | ioremap IMEM 会挂 |

`build-kernel.sh` 在 `olddefconfig` 之后会再强制：关 EFI、`DRM_MSM=m`、开 `FRAMEBUFFER_CONSOLE`。HUD 用 `KD_GRAPHICS` 把 tty 切走，fbcon 不再抢屏。

### 5.2 本地 DTS（`overlays/.../msm8996-xiaomi-gemini-local.dtsi`）

上游已有 `msm8996-xiaomi-gemini.dts`。本地只补：

- **USB**：删 `extcon`（tusb320 不就绪时 DWC3 永远 `-EPROBE_DEFER`，没有 UDC），`dr_mode = peripheral`，关掉 `typec`
- **远程处理器**：`adsp_pil` / `mss_pil` / `slpi_pil` disabled（umeko 笔记：ADSP 固件会卡开机；7.0 这些是 builtin）
- **WLED**：删 `interrupts`（7.0 解析到 OVP 后 `enable_irq` 不平衡 oops；6.1 是 `IRQ ovp not found`）
- **venus**：disabled（缺固件时 `sync_state pending` 拖死）
- **GPU 保持 enabled**：`msm_mdp` 必须绑 `b00000.gpu` 才会 `[drm] Initialized` / `msmdrmfb`
- **电池**：3000 mAh / 3.4–4.4 V（live dump）
- **不要** 加 `qcom,pshold@4ab000`

### 5.3 踩过、不要再做的

1. `--base 0x0`
2. ramdisk 放 `0x81000000`
3. earlycon / stdout 到 `0x7570000`
4. USB Type-C extcon 留着
5. `DRM_MSM=y` 抢 LK 面板
6. 用 RGB565 写 32 位 fb（只覆盖半屏，颜色还是品红）
7. ioctl 算出 0 像素再写（整屏变黑）
8. GDM / llvmpipe / `MESA_LOADER_DRIVER_OVERRIDE=msm` 在 HUD 阶段
9. configfs RNDIS 抢 `g_serial` 的 UDC
10. 两个 agetty 抢 `ttyGS0`（`autottyGS0` 已 mask，只留 `serial-getty@ttyGS0`）
11. 主机往 `/dev/ttyACM0` 打 `reboot-fastboot`（和 getty 抢字）
12. 刷 ginkgo 的 dtbo / vbmeta
13. 进了 LK 之后刷 userdata

---

## 6. 显示栈

硬件：JDI FHD **R63452** command mode，1080×1920。  
内核：`msm.ko` + `panel-jdi-fhd-r63452.ko`（模块名带 **fhd**，不是 `panel-jdi-r63452`）。

`display-unblank.sh`：

1. `modprobe panel-jdi-fhd-r63452`、`msm`、`ath10k_pci`
2. 等到 `/dev/dri/card0` 和 `/dev/fb0`
3. `fb0/blank = 0`，WLED `bl_power = 0`
4. 若存在 `/var/lib/gemini/hud.conf` 的 `bl=`，按百分比设亮度（最低约 1%）
5. `rfkill unblock`
6. `exec /usr/local/sbin/gemini-status`

像素必须 **`write(/dev/fb0)`**，格式 **小端 XRGB8888**（每像素 4 字节：B,G,R,X）。  
HUD 开 fb 后 `ioctl(tty, KDSETMODE, KD_GRAPHICS)`，避免 fbcon 盖画面。  
GPU 固件（`a530_pm4.fw` / `a530_pfp.fw` / `a530v3_gpmu.fw2` / zap）打进 initramfs，这样 `msm.ko` 不必等 userdata 上的 `/lib/firmware`。

早期探针是上绿下黄；黄条表示按键监听还活着。那套逻辑已收进 HUD：音量+ 仍进 fastboot。

GDM 会 modeset 到另一块 BO，把已验证的 fbdev 扫描冲成全黑，所以 overlay 里：

```text
gdm.service / gdm3.service / display-manager.service / getty@tty1.service → /dev/null
```

`display-unblank.service` 必须是 **Type=simple** 且长驻。以前 Type=oneshot 刷完绿就退出，音量键没人听。

---

## 7. HUD 怎么实现

### 7.1 它是什么

HUD 本体：`initramfs/gemini-status.c` + `gemini-status-gpu.c`，由 `build-initramfs.sh` 交叉编译成 `/usr/local/sbin/gemini-status`，放进 overlay。  
不依赖 X11 / Wayland。有 `out/sysroot-aarch64` 时走 **GBM + EGL + GLES2** 扫描；否则静态链接 stub，回退 CPU `write(fb0)`。  
2026-08-29 的掉帧、SSID、上下行、1 秒采样见 [`worklog-2026-08-29.md`](worklog-2026-08-29.md)。

systemd：`rootfs-overlay/etc/systemd/system/display-unblank.service`  
挂在 `multi-user.target` 和 `graphical.target`。

### 7.2 字体

HUD 不能依赖系统字体。`scripts/gen-gemini-status-font.py` 用 **Noto Sans CJK SC** 把 UI 用到的汉字 + ASCII 烘焙进 `initramfs/gemini-status-font.h`（三套：body / title / num）。

必须用带系统 PIL 的解释器，例如 **`/usr/bin/python3.14`**。当前 PATH 里的 python3.13 会踩错 PIL，字形被裁成细条。

改了界面文案后：

```bash
/usr/bin/python3.14 scripts/gen-gemini-status-font.py
./scripts/build-bootimg.sh
```

### 7.3 画面结构

- 右上角 **中 | EN** 切换；默认中文
- 标题下两行状态：`Ubuntu 26.04 · gemini`，下一行 `已运行 / 功耗 / 电量`
- **亮度滑块**（写 WLED sysfs），标签与滑条垂直居中
- 主卡片：Wi-Fi 状态（SSID、IP、MAC、网关、接口、已连时长、信号 `36% · -84 dBm · 5 GHz`）
- Wi-Fi 下方独立组件：左上传、右下载（1 秒平均，读 `/proc/net/dev`）
- 点卡片 → 底部托出选网列表（iOS 风 sheet）；加密网再滑出密码键盘
- 下方：Adreno 530、Kryo 每核、内存（数字 1 秒一跳，条子仍插值）
- 底栏：短按音量 + 进入 Fastboot

文案全部走 `T("中文", "English")`。语言和亮度写入 userdata：

```text
/var/lib/gemini/hud.conf
lang=zh
bl=80
```

`display-unblank.sh` 启动时先读 `bl=`，避免 HUD 起来前背光打满。

### 7.4 输入

打开 `/dev/input/event*`，`poll` 等触控和按键：

- 短按 **音量+**（以及音量− / Home）：`SYS_reboot(..., "bootloader")`，失败再 `exec reboot-fastboot`
- 触控：`ABS_MT_POSITION_*` + `ABS_MT_TRACKING_ID`；坐标按 `absmin/absmax` 映射到 1080×1920
- 列表可拖；密码页自绘键盘（Shift / 符号 / 删除）

**不要和电源一起按**——那是关机后进 LK 的硬件组合，和 HUD 无关。

### 7.5 异步任务（不阻塞绘制）

HUD 用 `fork` + `pipe` 跑外部命令，主循环 `poll_job()` 收输出：

| kind | 命令 | 用途 |
|------|------|------|
| 0 | `nmcli radio wifi on` | 开无线 |
| 1 | `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device` | 是否已连接 |
| 2 | `nmcli device wifi list --rescan yes` | 扫描 |
| 3 | `/usr/local/sbin/gemini-wifi-connect.sh` | 连接 |
| 4 | `iw dev IFACE link` | SSID / 频段 / 关联（不再用 station dump 当 SSID） |
| 5 | `gemini-wifi-connect.sh forget` | 忘记网络（删档，必要时 disconnect） |

同一时刻只跑一个 job。连接过程中不扫描，避免 ath10k 把关联打掉。

### 7.6 指标从哪读

| 项 | 来源 |
|----|------|
| CPU 总占用 / 每核 | `/proc/stat` 两次采样算 busy |
| 温度 | 扫 `/sys/class/thermal/thermal_zone*`，优先 type 含 cpu/kryo/krait 的，否则 tsens/soc |
| 内存 | `/proc/meminfo` 的 MemTotal − MemAvailable |
| GPU 频率 | 扫 clock sysfs，只收 **100–700 MHz**（Adreno 530 OPP 是 133–624；丢掉 27 MHz 这类 XO） |
| 运行时间 | `/proc/uptime` |
| IP / MAC / 网关 | ioctl、`/sys/class/net/*/address`、`/proc/net/route` |
| 上下行 | `/proc/net/dev` 指定 Wi-Fi 接口，1 秒窗口算 B/s |

界面上 CPU 一行类似：`Kryo · 20% · 48℃`。

### 7.7 帧率（发热的根因之一）

早期 HUD **60 fps 整屏 write(fb0)**，`gemini-status` 约占 63% CPU，大核顶到 ~2.0 GHz，温度 ~68℃。

现在按状态限帧，空闲用 `poll` 睡到下一帧：

| 状态 | 间隔 | 约帧率 |
|------|------|--------|
| 拖动手势 / sheet 动画 | 33 ms | ~30 fps |
| 连接中 loading | 80 ms | ~12 fps |
| 空闲 | 200 ms | **~5 fps** |

刷过含此改动 + `CONFIG_ARM_PSCI_CPUIDLE` 的 boot 后：HUD ~18% CPU，sysfs 出现 `WFI` + `cpu-sleep-0`，大核约 58℃。

### 7.8 进 fastboot

对齐 ginkgo 的复位字符串 **`bootloader`**，但 **跳过 systemd 关机**（7.0 上 DRM 关屏后可能永远不到复位）：

1. HUD 或 `/usr/local/sbin/reboot-fastboot`
2. `reboot-bootloader`（静态，`initramfs/reboot-bootloader.c`）
3. `syscall(SYS_reboot, ..., LINUX_REBOOT_CMD_RESTART2, "bootloader")`
4. pm8994 PON `mode-bootloader = <0x2>` → LK

成功判据：USB 变成 **`18d1:d00d`**，`fastboot devices` 能看到本机。  
屏上还有 FASTBOOT 字、USB 仍是 `0525:a4a7` → **不是** LK。

---

## 8. Wi-Fi

### 8.1 硬件与固件

- 芯片：QCA6174 hw3.2，PCIe `0000:01:00.0`
- 驱动：`ath10k_pci`（内建），接口 `wlp1s0`
- 固件：未压缩 `.bin` 放在 `rootfs-overlay/lib/firmware/ath10k/`，并打进 initramfs  
  （主机 `linux-firmware` 是 `.zst`，内核没开 `FW_LOADER_COMPRESS`）

### 8.2 为什么 HUD 里能 `nmcli`

HUD 没有图形 PolicyKit agent。overlay：

```ini
# rootfs-overlay/etc/NetworkManager/conf.d/99-gemini-auth.conf
[main]
auth-polkit=false
```

连接脚本 `rootfs-overlay/usr/local/sbin/gemini-wifi-connect.sh`：HUD 无 secret agent。Ubuntu 26.04 上 **netplan + NetworkManager 1.54** 的 `connection up` 必须再传 **`passwd-file`**，否则日志是 `password ... not given in 'passwd-file'`。不要把 `nmcli device wifi connect` 当主路径（会复用无密钥档案）。有密码时 `connection modify` 原地改 PSK（`psk-flags=0`）再 `up`。脚本报成功后 HUD 还要等 **live SSID 真匹配** 才关面板。忘记是独立 `forget SSID IFACE`，不先开关电台。日志：`/var/log/gemini-wifi.log`。当天踩坑与修复见 [`worklog-2026-08-29.md`](worklog-2026-08-29.md) §13 起。

### 8.3 「尚未连接」误判

`nmcli device` 会同时列出：

```text
wlp1s0:wifi:connected:某SSID
p2p-dev-wlp1s0:wifi-p2p:disconnected
```

旧代码 `strstr(type, "wifi")` 会匹配 `wifi-p2p`，后一行把状态盖成未连接。  
现在 **TYPE 必须 `strcmp == "wifi"`**，并跳过 `p2p-` 开头的接口。

### 8.4 信号百分比

机上实测过：`iw` **-84 dBm**（avg -85），速率约 13 Mbps MCS0；nmcli SIGNAL **36%**。  
旧 HUD 用线性映射 `(-90 … -30) → 0…100`，把 -84 算成 **~10%**，而且每 400 ms 用扫描列表覆盖 live RSSI。

现行规则（对齐 Android `WifiManager` / nmcli）：

```text
-100 dBm → 0%
 -55 dBm → 100%
pct = (dbm + 100) * 100 / 45
```

优先级：

1. `iw station dump` 的 **`signal avg`**（kind 4）
2. 否则 `signal:`
3. `/proc/net/wireless` 的 level
4. 扫描列表的 SIGNAL **不得覆盖** 已有 live dBm

卡片显示：`36% · -84 dBm · 5 GHz`。格数按 25/50/75 分档。  
**-84 dBm 本身偏弱是真的**，只有百分比曾经算错。

---

## 9. 用户空间 overlay 还塞了什么

每次 `switch_root` 前，`init.c` 把 ramdisk 的 `overlay/` 拷进 userdata。因此改 HUD / 脚本 / unit **只刷 boot 就会在下次开机生效**，不必重做 rootfs。

会拷进去的关键文件：

| 文件 | 作用 |
|------|------|
| `display-unblank.sh` + `.service` | 加载 DRM、启动 HUD |
| `gemini-wifi-connect.sh` | 无 PK agent 的 nmcli 连接 |
| `99-gemini-auth.conf` | `auth-polkit=false` |
| DRM 模块 `msm.ko` 等 | 7.0 模块树，避免整包 dump 到 userdata |
| ath10k 固件 | 见上 |
| `gemini-resize-root.service` | 扩 userdata 文件系统 |
| `serial-getty@ttyGS0` 自动登录 | USB 串口 |
| GNOME / Xorg / gdm 配置 | **备着，但 GDM 被 mask** |
| `usb-gadget-rndis.service` | **mask**，避免抢 UDC |
| `autottyGS0.service` | **mask**，避免双 getty |
| `KlipperScreen` / `xwayland_ks` | **mask** |

SSH：`ssh.service` enable。root 可用本机密码文件登录（文件 gitignored：`rootfs-overlay/etc/gemini-root-password`，**不要提交、不要写进文档**）。普通用户 `umeko` 的 SSH 当前不可用。

---

## 10. 刷机约定（日常）

用户说「进了」且主机看到 **`18d1:d00d`** / `fastboot devices` 有设备时：

```bash
fastboot flash boot out/boot.img && fastboot reboot
```

**只刷 boot，不要刷 userdata。** 26.04 根分区已经在机上。  
Sending 卡住：`killall -9 fastboot`，不要 usbreset。

两种进 LK：

| 操作 | 含义 |
|------|------|
| 关机后 **音量− + 电源** | 硬件进 LK，与 7.0 无关 |
| HUD 上 **只短按音量+** | 系统内 `reboot bootloader` 成功的证明 |

整盘换 Ubuntu 26.04 才用 `scripts/flash-ubuntu26.sh`（会擦 20.04）。不要对 gemini 刷 ginkgo 的 dtbo/vbmeta。

6.1 救援镜像：`inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img`。

---

## 11. 还没做

- GDM / gnome-shell 画在这块扫描上而不冲黑
- FG SOC 校准（电压/瓦数可用，容量常报 1%）
- 把 08-29 热替换的 HUD 打进 boot.img 并刷上（重启才会固化）
- 触控当桌面指针
- 蓝牙（6.1 dump 里 `hci0 Frame reassembly failed`）
- 基带 / ADSP / rmtfs
- 从 USB ACM 当交互串口打命令（kmsg 会淹没 tty）

原则：先保住扫描、HUD、Wi-Fi 和 reboot-fastboot，再碰桌面。

---

## 12. 相关文档

- [`device-inventory.md`](device-inventory.md) — TWRP 分区盘点
- [`hardware-dump-ubuntu.md`](hardware-dump-ubuntu.md) — 6.1 live dump
- [`upstream-research.md`](upstream-research.md) — 主线 DTS / msm8996-mainline
- [`bringup-plan-linux-7.0.md`](bringup-plan-linux-7.0.md) — 原计划
- [`linux-7.0-bringup.md`](linux-7.0-bringup.md) — 第一次 7.0 启动
- [`display-and-reboot-fastboot-7.0.md`](display-and-reboot-fastboot-7.0.md) — 绿黄探针与音量+
- [`reboot-fastboot.md`](reboot-fastboot.md) — 进 LK 的命令约定
- [`worklog-2026-08-29.md`](worklog-2026-08-29.md) — HUD 掉帧 / SSID / 上下行 / 1 秒采样
- [`worklog-2026-08-28.md`](worklog-2026-08-28.md) — 电量计 / HUD 打磨 / Docker / Adreno 3D
- [`gnome-desktop.md`](gnome-desktop.md) — GNOME overlay（尚未接上）
