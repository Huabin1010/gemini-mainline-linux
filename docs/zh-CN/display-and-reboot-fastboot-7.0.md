**语言：** [English](../display-and-reboot-fastboot-7.0.md) | 简体中文

# Linux 7.0 显示扫描 + 系统内 reboot-fastboot（gemini）

记录时间：2026-08-28（CST）。  
机器：Xiaomi Mi 5（`gemini`，MSM8996 / Snapdragon 820）。  
对照内核：分区上仍是 **6.1.14-umeko-rv0**（不要 `fastboot flash`）。  
本次内核：`7.0.0-umeko-rv0-dirty`，只 `fastboot boot out/boot.img`。

本文记录从「背光黑屏」到「整屏可画」以及 **在 7.0 用户态按音量 + 进入真正的 LK fastboot** 的实测。第一次进 Ubuntu 的记录见 [`linux-7.0-bringup.md`](linux-7.0-bringup.md)；进 fastboot 的命令约定见 [`reboot-fastboot.md`](reboot-fastboot.md)。

---

## 1. 当次结论

| 项 | 结果 |
|----|------|
| 启动 | `fastboot boot`，未覆盖 6.1 |
| 根分区 | userdata UUID 随重装变化 |
| USB 系统态 | CDC ACM `0525:a4a7`（`bcdDevice` 7.0 为 `7.00`） |
| USB fastboot | **`18d1:d00d`**（LK） |
| 面板 | JDI FHD R63452，MSM DRM fbdev `msmdrmfb`，1080×1920 **XRGB8888** |
| 扫描 | CPU `write(/dev/fb0)` 可见；整屏绿 / 底黄条已出 |
| 系统内进 fastboot | **音量 +** → `reboot-fastboot` → USB `18d1:d00d`（2026-08-28 19:24 实测） |
| GDM / GNOME | **未接上**（曾抢屏把扫描冲成全黑，现已 mask） |

绿黄屏是探针，不是桌面。桌面上的「重启到 Fastboot」图标还没在 7.0 上点过。

---

## 2. 两种「进 fastboot」不要混

| 操作 | 实际进的是什么 | USB |
|------|----------------|-----|
| 关机后 **音量 − + 电源** | LK 硬件组合，与 7.0 用户态无关 | `18d1:d00d` |
| 绿黄屏上 **只短按音量 +**（不要按电源） | 7.0 里的 `reboot-fastboot` | 成功时变成 `18d1:d00d` |
| 屏上 FASTBOOT 字、全黑、USB 仍是 `0525:a4a7` | **不是** LK fastboot | — |

本次验证成功的是第二行。第一行只能说明 bootloader 钥匙还在，不能证明系统内 reboot 字符串通了。

---

## 3. 显示：现象时间线

| 现象 | 原因 |
|------|------|
| 背光亮、画面全黑 | MDP 已 modeset，扫描缓冲是黑的；或 GDM/X 用另一块 BO 把 fbdev 冲掉 |
| 上半屏紫、下半屏黑（无「背光」观感） | 用 RGB565 `0x07E0` 只写了 `1080×1920×2` 字节；缓冲实际是 32 位，只覆盖一半。`0x07E007E0` 解成 XRGB 是品红 |
| 全黑有背光（GDM 解开死锁之后） | GDM/modesetting 起来后翻到黑色 plane；探针被盖掉 |
| 整屏紫 | 同一套 `0xE007` 重复写满 `1080×1920×4` 字节 |
| 整屏绿 | 按 XRGB8888 小端写 `B,G,R,X = 00,FF,00,00` |
| 上绿下黄 + 音量 + 进 fastboot | `display-unblank` 长驻听输入，黄条表示 listener 活着 |

**已经证明的事：** MSM fbdev 扫描通路通；像素格式是 **32-bit XRGB8888**；不要用 ioctl 算出来的 0 像素去覆盖（会整屏变黑）。

**还没证明：** GDM/Xorg/gnome-shell 能画在这块扫描上而不把它冲黑。

---

## 4. 显示：不要再做的事

1. 不要把 `DRM_MSM` 编成 builtin 去抢 LK 面板（早期会：USB 有、ACM 空、屏停在 LK FASTBOOT 字）。
2. 不要开 `FRAMEBUFFER_CONSOLE` 往 GPU 显存做 `sys_imageblit`（会卡在 `framebuffer is not in virtual address space`）。
3. 不要给 WLED 配 OVP 中断（7.0 会 `wled_ovp_work` → unbalanced `enable_irq`；6.1 是 `IRQ ovp not found`）。overlay 里 `&pmi8994_wled` 删掉 `interrupts` / `interrupt-names`。
4. 不要 `qcom,pshold@4ab000`、不要为进 fastboot 去 ioremap IMEM。
5. 不要从主机往 `/dev/ttyACM0` 打 `reboot-fastboot`（和 getty 抢字）。
6. 不要 `fastboot flash` 覆盖分区上的 6.1。
7. Sending 卡住：`killall -9 fastboot`，不要 usbreset。
8. 进 fastboot **不必**先开 6.1 桌面。屏好或已在 `18d1:d00d` → 直接 `fastboot boot`。
9. GDM 不要用 `GALLIUM_DRIVER=llvmpipe`（包可能不存在，GDM 直接起不来）。`MESA_LOADER_DRIVER_OVERRIDE=msm` 会弄坏软件 GL。
10. 不要在 `display-unblank`（`Before=gdm`）里 `systemctl start gdm`：oneshot 等 GDM，GDM 等 oneshot，死锁。
11. 探针进程必须 **Type=simple 长驻**。以前 Type=oneshot 刷完绿就退出，音量键没人听，看起来像「按键没反应」。

---

## 5. 当前显示栈（2026-08-28 晚）

内核：

- `CONFIG_DRM_MSM=m`、`CONFIG_DRM_PANEL_JDI_R63452=m`（rootfs 起来后再 `modprobe`）
- `CONFIG_DRM_FBDEV_EMULATION=y`（fbdev 做第一次 modeset + 背光）
- `# CONFIG_FRAMEBUFFER_CONSOLE is not set`
- cmdline 只有 `console=ttyGS0,115200`（不要 `tty0`）
- `# CONFIG_POWER_RESET_QCOM_IMEM is not set`；`CONFIG_POWER_RESET_MSM` + `CONFIG_POWER_RESET_QCOM_PON`
- `olddefconfig` 会把 fbcon 相关项打回默认，必须在 **最后一次 olddefconfig 之后** 再 `scripts/config --disable FRAMEBUFFER_CONSOLE`

设备树 / 驱动：

- 面板模块名是 **`panel-jdi-fhd-r63452`**，不是 `panel-jdi-r63452`
- `&venus { status = "disabled"; }`（缺固件时 `sync_state pending`）
- GPU 保持 enabled（`msm_mdp` 要绑 GPU）
- ADSP / MSS / SLPI disabled；USB `dr_mode = peripheral`

用户态探针（GDM 仍 mask）：

- `display-unblank.service`：**Type=simple**，`ExecStart=/usr/local/sbin/display-unblank.sh`
- 脚本 `modprobe` 面板 + `msm`，等 `/dev/dri/card0` 和 `/dev/fb0`，刷 **上绿下黄**，然后 Python 听：
  - 短按 `KEY_VOLUMEUP` / `KEY_VOLUMEDOWN` / `KEY_HOME`
  - 或点触 `ABS_MT_TRACKING_ID`
  - 然后 `exec /usr/local/sbin/reboot-fastboot`
- GDM / gdm3 / display-manager 在 overlay 里 mask 成 `/dev/null`（GDM 会把已验证的扫描冲黑）
- 日志：`/var/log/gemini-display.log`、`/var/log/reboot-fastboot.log`

像素：

```text
XRGB8888 LE，1080×1920×4 字节
绿：00 FF 00 00
黄条：00 FF FF 00（底部 240 行，表示 listener 还活着）
```

若只有全绿、没有黄条：listener 没起来，音量键不会进 fastboot。

---

## 6. reboot-fastboot 怎么走通的

对齐 ginkgo 的命令字符串 **`bootloader`**，但 **跳过 systemd 关机**（7.0 上 DRM 关屏后可能永远不到复位）。

1. `/usr/local/sbin/reboot-fastboot`（root / sudoers 免密）
2. `exec /usr/local/sbin/reboot-bootloader`（静态 aarch64）
3. `SYS_reboot` + `LINUX_REBOOT_CMD_RESTART2` + `"bootloader"`
4. pm8994 PON `mode-bootloader = <0x2>`，再复位进 LK

源码：`initramfs/reboot-bootloader.c`，由 `scripts/build-initramfs.sh` 交叉编译进 overlay。

6.1 上 `sudo reboot bootloader`（只走 PON）已经能进 LK。7.0 上本次用音量 + 调同一条用户态路径，USB 变为 `18d1:d00d`。

主机 `scripts/reboot-fastboot.sh` **不要写 ACM**，只等 `fastboot devices`。

按键：音量 + 是 DT 里 `gpio-keys` / `KEY_VOLUMEUP`；音量 − 是 `pm8994_resin` / `KEY_VOLUMEDOWN`。两者短按都可以进；**不要和电源一起按**（那是 LK 硬件组合）。

---

## 7. 构建与 ram-boot

```bash
./scripts/build-kernel.sh    # 改了 msm.ko / fbdev / config 才需要
./scripts/build-bootimg.sh   # 只改 overlay / initramfs 即可
fastboot boot out/boot.img   # 已在 18d1:d00d 时直接 boot，不必先绕 6.1
```

boot 头必须是：

```text
ANDROID! v0  kernel@0x80008000  ramdisk@0x84000000  tags@0x80000100  pagesize=4096
```

`--base 0x80000000`。cmdline 不要 `panic=10`、不要 `nowatchdog`。

6.1 备份：`inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img`。

---

## 8. 还没做

- GDM / Xorg fbdev / GNOME：能 modeset，但不能把扫描冲黑
- 桌面图标 `reboot-fastboot.desktop` 未在 7.0 上点过（音量 + 已等价验证脚本）
- 把 7.0 boot **写入分区**（仍禁止，除非明确要求 flash）
- 触控除「点一下进 fastboot」外未当桌面指针用
- Adreno glamor / 真 3D：仍用 CPU 写 fb0
- ACM 被 kmsg 淹没，主机不宜当交互串口打命令

---

## 9. 给后续的原则

1. 开机/重启不要为 fastboot 去 ioremap 新 MMIO。
2. GPU 保持 enabled。
3. 屏上 FASTBOOT / 黑屏 ≠ 内核没起来；先看 USB `0525:a4a7` vs `18d1:d00d`。
4. 用户说「进了 / 好了 / 进 fastboot 了」且 USB 是 `18d1:d00d` → 直接 `fastboot boot`。
5. 用户用音量 − + 电源进的，只说明 LK，不说明系统内 reboot。
6. 先保住扫描和 reboot-fastboot，再碰 GDM。
