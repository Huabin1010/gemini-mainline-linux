**语言：** [English](../linux-7.0-bringup.md) | 简体中文

# Linux 7.0 第一次成功启动记录（gemini）

记录时间：2026-08-27 23:55（CST）。  
机器：Xiaomi Mi 5（`gemini`，MSM8996 / Snapdragon 820），`hwversion=1.4.0`。  
结果：**`fastboot boot` 进入 Ubuntu 20.04.6，内核 `7.0.0-umeko-rv0-dirty`，USB 串口自动登录 `umeko`，DRM 切到 `msmdrmfb`。分区上的 6.1 boot 没有被覆盖。**

本文把从卡死到成功的对照、误判和最终改动写清楚，方便以后复现或给别的 MSM8996 机参考。

相关文档：

- 设备盘点：[`device-inventory.md`](device-inventory.md)
- 6.1 live dump：[`hardware-dump-ubuntu.md`](hardware-dump-ubuntu.md)
- 上游调研：[`upstream-research.md`](upstream-research.md)
- 原计划：[`bringup-plan-linux-7.0.md`](bringup-plan-linux-7.0.md)
- umeko 移植笔记：[KlipperPhonesLinux `gemini.note.md`](https://github.com/umeiko/KlipperPhonesLinux/blob/main/LinuxKernels/msm8996/gemini.note.md)

---

## 1. 成功判据（当次实测）

主机侧约 **7 秒**出现 CDC ACM `0525:a4a7`（`/dev/ttyACM0`）。串口抓到完整 dmesg 和 systemd，并自动登录：

```text
Linux version 7.0.0-umeko-rv0-dirty ... #6 SMP PREEMPT Thu Aug 27 23:31:40 CST 2026
Machine model: Xiaomi Mi 5
...
Welcome to Ubuntu 20.04.6 LTS (GNU/Linux 7.0.0-umeko-rv0-dirty aarch64)
umeko@XiaoMi5-Ubuntu:~$
```

内核侧：

| 项目 | 7.0 当次 |
|------|----------|
| 启动方式 | `fastboot boot out/boot.img`（**没有** `fastboot flash`） |
| 根分区 | UFS `sda15`，UUID 随重装变化，EXT4 已 rw 挂上 |
| USB | 内核 `g_serial`；systemd `autottyGS0.service` 自动登录 |
| 显示 | `msm_mdp` 绑上 DSI + GPU；`[drm] Initialized msm 1.13.0`；`fb0: msmdrmfb`；`Console: switching to colour frame buffer device 135x120` |
| 触控 | `Synaptics S3330`（rmi4，i2c `2-0020`）已注册 |
| 马达 | `drv260x` 已 probe（启动会振动） |
| 用户空间 | systemd 245.4，hostname `XiaoMi5-Ubuntu` |

命令行（LK 还会追加 Android 参数）：

```text
console=tty0 console=ttyGS0,115200 ignore_loglevel loglevel=8
clk_ignore_unused pd_ignore_unused
root=/dev/disk/by-partlabel/userdata rootwait rw maxcpus=4
```

LK 追加里仍有现网 6.1 同款面板参数：

```text
mdss_mdp.panel=1:dsi:0:qcom,mdss_dsi_jdi_fhd_r63452_cmd:1:none:cfg:single_dsi
```

boot 头必须是：

```text
ANDROID! v0  kernel@0x80008000  ramdisk@0x84000000  tags@0x80000100  pagesize=4096
```

---

## 2. 基线：为什么 6.1 能用

现网能用的是 umeko / KlipperPhonesLinux 的 `6.1.14-umeko-rv0`（2024-05-07），rootfs 在 userdata。备份：

```text
inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img
SHA256 9871a481dab9172411464ebdc7f35eb6ee404abbf84fd62e6b969e8c836c1ef9
```

对照实验：`fastboot boot` 这份 6.1，大约 6 秒就出 ACM。所以 ram-boot 路径没问题，卡死的是 7.0 自己。

6.1 live dump（`inventory/2026-08-27-ubuntu/hw-dump/dmesg.txt`）里和本次成败直接相关的几行：

```text
[    6.103994] UDC core: g_serial: couldn't find an available UDC
[    7.210315] g_serial gadget.0: Gadget Serial v2.4
[    7.210334] g_serial gadget.0: g_serial ready
[    7.221462] Run /init as init process
...
[   14.654128] msm_mdp 901000.mdp: bound 994000.dsi (ops dsi_ops [msm])
[   14.666826] msm_mdp 901000.mdp: bound b00000.gpu (ops a3xx_ops [msm])
[   14.862707] [drm] Initialized msm 1.9.0 ...
[   14.873262] loaded qcom/a530_pm4.fw
[   14.874011] loaded qcom/a530_pfp.fw
[   14.874723] loaded qcom/a530v3_gpmu.fw2
[   15.172112] Console: switching to colour frame buffer device 135x120
[   15.240084] msm_mdp 901000.mdp: [drm] fb0: msmdrmfb frame buffer device
```

要点：

1. USB **不是** initramfs 里手搓 configfs ACM。是内核 **`CONFIG_USB_G_SERIAL=y`**，VID/PID 正好是 `0525:a4a7`。PHY 起来之后 `g_serial` 自己占 UDC，用户态 `autottyGS0.service` 在 `ttyGS0` 上 `login -f umeko`。
2. 显示是 MSM DRM。`msm_mdp` **必须绑上 GPU**（`b00000.gpu`）才会 `[drm] Initialized` 并出现 `msmdrmfb`。固件来自 userdata 的 `/lib/firmware/qcom/`。DRM 在 6.1 里是模块，rootfs 挂上之后再加载。
3. `CONFIG_EFI is not set`。`ARM64_VA_BITS=48`。boot 头 `kernel@0x80008000`。
4. 面板只有 **JDI `jdi,fhd-r63452`**。真调试 UART 不是蓝牙口 `0x7570000`。
5. umeko 笔记：ADSP 固件会让开机卡死，现网也缺 `adsp.mbn`（dmesg 里 PIL 失败但不挡启动，因为 6.1 里 ADSP 是模块）。

---

## 3. 失败时间线（都是 `fastboot boot`，没 flash）

| 次序 | 改动 | 现象 |
|------|------|------|
| 1 | 7.0 默认打包，`--base 0x0`，还加了 BT UART earlycon | USB 立刻没了，卡死 |
| 2 | `kernel@0x80008000`，去掉 earlycon | 仍无 USB |
| 3 | `initcall_blacklist` 关 DRM | 仍无 USB |
| 4 | 关 EFI、关 `DRM_MSM` | 仍无 USB |
| 5 | ramdisk 挪到 `0x84000000` | 仍无 USB |
| 6 | 用 umeko `.config` 做底，Image 从 ~42 MiB 收到 ~25 MiB | 振动后弹回 fastboot（内核已跑） |
| 7 | 去掉 `panic=10`，initramfs 提前 ACM | ~48 s 无 USB，也不弹回 |
| 8 | DTS `dr_mode=peripheral` + `nowatchdog` | 无 USB，不弹回 |
| 9 | 关 ADSP/MSS/SLPI | ~28 s 弹回 fastboot；有振动，屏幕仍是 fastboot 字样 |
| 10 | 去掉 USB extcon（`tusb320`），**去掉 `nowatchdog`** | **ACM 枚举成功**，但串口读不到字；屏幕仍是 LK 的 fastboot 画面 |
| 11 | 开 DRM、关 GPU、initramfs 抢 UDC 做 configfs ACM | ACM 在，串口仍空，屏幕仍 fastboot 字样 |
| 12 | 对齐 6.1：`g_serial` 占 UDC、GPU 打开、initramfs 带 Adreno 固件 | **成功** |

中间几次「屏幕还是 fastboot 字样」容易误判成内核没起来。LK 的 splash **不会自己擦掉**。没有 DRM modeset 时，硬件一直显示最后一帧 LK 画面；USB 已经在工作。

---

## 4. 根因（对照 6.1 才看清）

### 4.1 boot 头把内核放到非 DRAM

`--base 0x0` 会把内核放到 `0x8000`，那不是 MSM8996 的 DRAM。umeko 是 `--base 0x80000000` → `kernel@0x80008000`。写成 `0x0`，LK 一跳就死，USB 马上没。

### 4.2 7.0 Image 太大，盖掉 ramdisk

umeko 用 `ramdisk@0x81000000`（距内核 16 MiB）。7.0 未压缩 `Image` 一度约 42 MiB，解压会盖掉 ramdisk。后来瘦核到约 25 MiB，仍把 ramdisk 放在 **`0x84000000`（+64 MiB）**。

### 4.3 `0x7570000` 是蓝牙 UART，不是 console

`blsp1_uart2` 接 QCA6174。earlycon/ttyMSM0 打到这里会早死。cmdline 只留 `console=tty0`，成功后再加 `console=ttyGS0,115200`。

真调试口是 GPIO4/5、`blsp2_uart2` @ `0x75b0000`，原理图空贴 `ISL54062` / `S700_NM`。本次没焊。

### 4.4 Type-C extcon 让 DWC3 永远 defer

上游 DTS：

```dts
&usb3 { extcon = <&typec>; };
&usb3_dwc3 { extcon = <&typec>; };
```

`typec@47` 是 `ti,tusb320l`，和马达同一条 I2C。7.0 上 tusb320 不就绪时，`dwc3_get_extcon()` 一直 `-EPROBE_DEFER`，**没有 UDC**。`g_serial` 6.1 里也会先打 `couldn't find an available UDC`，等 PHY 起来再绑。7.0 若再被 extcon 卡住，UDC 永远出不来。

overlay 删除 `extcon`，并 `dr_mode = "peripheral"`。fastboot 之后口已经是 device 模式。

### 4.5 `nowatchdog` 让 LK 留下的 KPSS WDT 没人喂

LK 跳内核前已经打开硬件看门狗。`CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED=y` 要靠 Linux `qcom-wdt` 接管。传 `nowatchdog` 后驱动不喂，大约 **28 秒 bite，弹回 fastboot**。不要关、也不要 `nowatchdog`。

`panic=10` 会在 oops 后重启，看起来也像「弹回 fastboot」。调试阶段不要加。

### 4.6 7.0 把 ADSP/MSS/SLPI 编进内核

umeko：`CONFIG_QCOM_Q6V5_ADSP=m`。  
7.0 fragment 一度 `=y`，DTS 还写着 `adsp.mbn`。PIL 在 initramfs / USB 之前就会跑，笔记里的「ADSP 卡米」会变成死等。overlay 里 `status = "disabled"`。

### 4.7 自己做 configfs ACM，抢走了 `g_serial` 的 UDC

这是「有 `0525:a4a7` 却读不到一个字节」的原因。

6.1 的 `0525:a4a7` 来自 **`g_serial`**。7.0 内核其实已经链了 `g_serial`（umeko `.config` 底带了 `CONFIG_USB_G_SERIAL=y`），但 initramfs 又 `mkdir usb_gadget/gemini` 绑同一个 UDC。主机能枚举 ACM，gadget 侧 `ttyGS0` 数据通路却是空的。

另外：configfs ACM 在主机打开口之前用非阻塞 write，日志会直接丢掉，看起来也像「串口没字」。

**做法：initramfs 不要绑 UDC。** 让 `g_serial` 独占，用户态用 `autottyGS0.service`。不要再启 `usb-gadget-rndis.service` 去抢 UDC。

### 4.8 关掉 GPU，DRM 永远完不成

这是「USB 通了、屏幕永远是 fastboot 字样」的原因。

`msm` 驱动默认 **一块 DRM 设备同时管显示和 GPU**。6.1 dmesg 顺序是：绑 DSI → **绑 GPU** → `Initialized msm` → 加载 pm4/pfp/gpmu → 切 fbcon → `msmdrmfb`。

overlay 里 `&gpu { status = "disabled"; }` 之后，`msm_mdp` 等不到 GPU component，LK splash 一直留着。

GPU 还要固件。编进内核时 probe 发生在 userdata 挂上之前，必须把固件放进 **initramfs** `/lib/firmware/qcom/`：

- `a530_pm4.fw`
- `a530_pfp.fw`
- `a530v3_gpmu.fw2`
- `msm8996/gemini/a530_zap.mbn`

当次 pm4/pfp/gpmu 加载成功。zap 用了 linux-firmware 的 **APQ8096 通用包**，失败：

```text
adreno b00000.gpu: error -5 initializing firmware qcom/msm8996/gemini/a530_zap.mbn
msm_mdp: [drm:adreno_load_gpu] *ERROR* gpu hw init failed: -5
```

尽管如此仍出现了 `msmdrmfb` 和 fbcon 切换，所以扫描输出不依赖 zap 完全成功。机上 userdata 里有真正的 gemini `a530_zap.mbn`，下一步应改用那份。

### 4.9 其它曾误判、后来排除的

- DTB `qcom,msm-id` / `board-id`：与 umeko 一致（`0xf6 0x30001`，board 31 和 32），不是 LK 选错 DTB。
- initramfs 没有 udev，`/dev/disk/by-uuid/...` 不会出现；要靠 `/dev/sda15` 或 `PARTNAME=userdata`。已写进 `initramfs/init.c`。
- 振动只说明 `drv260x` probe 到了，不代表 USB/DRM 成功。
- 关 `DRM_MSM` 并不能单独救启动；真正挡 USB 的是加载地址、extcon、看门狗、ADSP、以及后来抢 UDC。

---

## 5. 最终改动清单

### 5.1 打包（`scripts/build-bootimg.sh`）

- `--base 0x80000000`，`kernel_offset 0x8000`，`ramdisk_offset 0x04000000`，`pagesize 4096`
- `cat Image.gz dtb` → `Image.gz-dtb`
- 检查未压缩 `Image` 小于 ramdisk 间隙
- cmdline 见第 1 节；**不要** `panic=10`，**不要** `nowatchdog`

### 5.2 内核 fragment（`config/gemini.fragment`）

- `ARM64_VA_BITS=48`，`# CONFIG_EFI is not set`
- `USB_G_SERIAL=y`，`U_SERIAL_CONSOLE=y`（与 umeko 6.1 一致）
- `DRM_MSM=y`，`DRM_MSM_MDP5`，`DRM_MSM_DSI`，`DRM_MSM_DSI_14NM_PHY`，`DRM_PANEL_JDI_R63452=y`，`BACKLIGHT_QCOM_WLED=y`，`DRM_FBDEV_EMULATION=y`
- UFS / DWC3 / ATH10K_PCI / RMI4 仍为 built-in 或按 fragment

`scripts/build-kernel.sh` 在 merge 后强制：关 EFI；开上述 DRM / g_serial。

### 5.3 DTS overlay（`msm8996-xiaomi-gemini-local.dtsi`）

- 不要把 stdout 指到蓝牙 UART
- `&usb3` / `&usb3_dwc3`：删除 `extcon`；`dr_mode = "peripheral"`；`&typec { status = "disabled"; }`
- `&adsp_pil` / `&mss_pil` / `&slpi_pil`：`disabled`
- **GPU 保持 enabled**（common dtsi 已 `okay`，overlay 不再关掉）

### 5.4 initramfs

- **不要** configfs 绑 UDC
- 挂 proc/sys/dev → 找 `sda15` / PARTNAME=userdata → 挂 ext4 → 把 `rootfs-overlay/` 拷进 userdata → `exec /sbin/init`
- overlay：`autottyGS0.service` 自动登录 `umeko`；**mask** `usb-gadget-rndis.service`（避免再抢 UDC）；mask KlipperScreen
- 加入 Adreno 固件：`inventory/firmware/qcom/`（来自 linux-firmware）

### 5.5 固件文件

```text
inventory/firmware/qcom/a530_pm4.fw
inventory/firmware/qcom/a530_pfp.fw
inventory/firmware/qcom/a530v3_gpmu.fw2
inventory/firmware/qcom/apq8096/a530_zap.mbn
inventory/firmware/qcom/msm8996/gemini/a530_zap.mbn   # 当前是通用包的副本
```

来源：`linux-firmware.git` 的 `qcom/`。gemini 设备专用 zap 仍应以 userdata 里那份为准。

---

## 6. 当次 7.0 dmesg 摘录（成功那一枪）

USB 串口约 7.1 s 打开后抓到（节选）：

```text
[    2.227584] msm_mdp 901000.display-controller: bound 994000.dsi (ops dsi_ops)
[    2.234631] msm_mdp 901000.display-controller: bound b00000.gpu (ops a3xx_ops)
[    2.234895] msm_mdp 901000.display-controller: [drm:mdp5_kms_init] MDP5 version v1.7
[    2.254358] [drm] Initialized msm 1.13.0 for 901000.display-controller on minor 0
[    2.254679] loaded qcom/a530_pm4.fw from new location
[    2.254912] loaded qcom/a530_pfp.fw from new location
[    2.255043] loaded qcom/a530v3_gpmu.fw2 from new location
[    2.263066] adreno b00000.gpu: error -5 initializing firmware qcom/msm8996/gemini/a530_zap.mbn
[    2.263190] msm_mdp: [drm:adreno_load_gpu] *ERROR* gpu hw init failed: -5
[    2.565147] Console: switching to colour frame buffer device 135x120
[    2.611062] msm_mdp: [drm] fb0: msmdrmfb frame buffer device
initramfs: looking for userdata
initramfs: USB console on ttyGS0
initramfs: alive fb0=1 dri=1
initramfs: root /dev/sda15
[    3.007015] EXT4-fs (sda15): mounted filesystem 93afcbbe-... r/w
initramfs: exec /sbin/init
[    3.249289] systemd 245.4-4ubuntu3.22 ... Detected architecture arm64.
[    3.294588] systemd[1]: Set hostname to <XiaoMi5-Ubuntu>.
[ OK ] Started USB g_serial login on ttyGS0 (umeko 6.1 path)
[ OK ] Finished Unblank fb0 before GDM
Welcome to Ubuntu 20.04.6 LTS (GNU/Linux 7.0.0-umeko-rv0-dirty aarch64)
```

触控：`Synaptics S3330` fw id 2613032（与 6.1 dump 一致）。  
UFS：Toshiba `THGLF2G9J8LBATRH`，`sda15` 为 userdata。

其它噪音（6.1 也有类似的，不挡启动）：

- `psci: failed to set PC mode: -1`
- `lp5562 ... failed with error -22`
- `adreno: supply vdd/vddcx not found, using dummy regulator`
- `msm_dsi: supply vcca not found`
- `Unbalanced enable for IRQ 65`（`wled_ovp_work`）
- `fb0: sys_imageblit: framebuffer is not in virtual address space`（fbcon 软绘制告警；KMS 仍注册了 fb0）
- `regulatory.db` 未进 initramfs

---

## 7. 怎么再启动 / 怎么回去 6.1

试启动（推荐，不覆盖分区）：

```bash
./scripts/build-kernel.sh
./scripts/build-bootimg.sh
fastboot boot out/boot.img
```

主机：

```bash
# 没有 picocom 时
screen /dev/ttyACM0 115200
# 退出：Ctrl+A，K，Y
```

刷回 6.1（分区上的备份一直在）：

```bash
fastboot flash boot inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img
fastboot reboot
```

长按电源可离开卡死的 ram-boot。TWRP 仍可当救援。

从 Ubuntu 进 fastboot（不必按键）：机上 `reboot-fastboot`，或电脑 `./scripts/reboot-fastboot.sh`。说明见 [`reboot-fastboot.md`](reboot-fastboot.md)。

---

## 8. 还没做完的

1. **gemini 专用 `a530_zap.mbn`**：用 userdata `/lib/firmware/qcom/msm8996/gemini/a530_zap.mbn` 替换 initramfs 里的通用包，让 GPU hw init 不再 -5。然后再开 Xorg/GNOME glamor。
2. **GNOME / GDM**：overlay 已打进 userdata（自动登录、mask KlipperScreen、unblank fb0）。当次 systemd 已跑 unblank；桌面是否出来要看屏幕和 zap。
3. **Wi-Fi**：6.1 是 `ath10k_pci` QCA6174。7.0 当次串口截断前已有 PCIe 枚举；`regulatory.db` 建议放进 initramfs。电池过旧时 umeko 笔记说 Wi-Fi 会起不来。
4. **ADSP/基带/SLPI**：为启动稳定性关掉。需要音频/传感器时再单独开，且不要把 ADSP 编成 built-in 却没有 `adsp.mbn`。
5. **软关机**：umeko issue #1，6.1 后期内核修过；7.0 未验证。
6. **不要 `fastboot flash`** 覆盖 6.1，直到 zap/桌面稳定。

---

## 9. 以后不要再踩的坑（短列表）

1. `mkbootimg --base` 必须 `0x80000000`。
2. 大 Image 不要再用 `ramdisk@0x81000000`。
3. 不要 earlycon 到 `0x7570000`。
4. 不要 `nowatchdog`，不要随便 `panic=10`。
5. 不要在 7.0 里让 ADSP PIL 以 built-in 抢在 USB 前面。
6. 不要用 configfs 和 `g_serial` 抢同一个 UDC。
7. 不要为了「先亮屏」关掉 GPU；MSM8996 的 `msm_mdp` 要绑 GPU 才出 fb。
8. 屏幕仍显示 fastboot 字样 ≠ 内核没起来；先看 USB / pstore。
9. LK 不支持 `fastboot fetch`，boot 备份走 TWRP `dd`。
10. **不要在 msm8996 开机路径上额外 ioremap MMIO。** `qcom,pshold@4ab000` 和 IMEM `syscon@0x08600000`（`syscon-reboot-mode` / cookie `0x77665500`）都试过：USB `0525:a4a7` 能枚举，ACM 没数据，屏停在 LK 的 FASTBOOT 字。后面几枪即使 DTB 已干净，也要先 `fastboot reboot` 回 6.1 把 MDSS 拉回来。进 fastboot 用 misc 上的 Android BCB，不要在 DTB 里加这些节点。

---

## 10. 2026-08-28：成功之后又卡在 FASTBOOT 字样

### 现象

第一次 7.0 成功（§1）之后，为了对齐 ginkgo 的 `reboot-fastboot`，在 DTS overlay 里加了下游同款：

```dts
&soc {
	restart@4ab000 {
		compatible = "qcom,pshold";
		reg = <0x004ab000 0x4>;
	};
};
```

`fastboot boot` 之后：

- 主机立刻看到 `0525:a4a7`（内核 `g_serial` 已经起来）
- `/dev/ttyACM0` 打不开 / 读到 0 字节
- 屏幕仍是 LK 的 **FASTBOOT** 字（没有 `msmdrmfb`）

当时内核仍是成功那枪的 `#6`（23:31，只重编了 DTB）。initramfs 里 Adreno 固件还在。

### 对照实验

| 改动 | 结果 |
|------|------|
| 去掉 pshold，其余不变 | 仍无显示、ACM 无数据 |
| 再从 initramfs 拿掉 `reboot-fastboot` 用户态文件 | 仍失败 |
| `fastboot reboot` 回分区上的 6.1 | **屏幕和串口立刻恢复** |

结论：用户态脚本不是根因。pshold 那一枪把 MDSS/GPU 留在半初始化状态；后面几枪 7.0 即使 DTB 已经干净，也接不走 LK splash。6.1 的 DRM 是模块，probe 顺序不同，能把面板拉回来。

### 修复

- DTS **不再**声明 `qcom,pshold`，也**不要**开机映射 IMEM。
- 内核继续用 `#6`（未因这次重编 Image）。
- `reboot-fastboot` 只写 misc BCB `bootonce-bootloader` 再普通 `reboot`。
- 6.1 把显示恢复之后，再 `fastboot boot` 这份 7.0。

同一天稍后又加过 IMEM `sram@8600000` / `syscon-reboot-mode`，现象与 pshold 完全一样。从那枪卡死后直接 ram-boot 干净 DTB 仍是「USB 有、ACM 空」；必须先回 6.1。

