**语言：** [English](../gnome-desktop.md) | 简体中文

# GNOME 桌面（刷 7.0 后）

现有 Ubuntu 20.04 rootfs **还没装** `gdm3` / `gnome-shell`。当前图形是 KlipperScreen。

准备方式（对齐 ginkgo）：

1. `rootfs-overlay/`：GDM 自动登录 `umeko`、Wayland、modesetting+glamor、缩放 2、屏幕键盘、关掉超时锁屏；mask 掉 `KlipperScreen` / `xwayland_ks`。
2. 第一次开机 `gemini-gnome-setup.service` 等网络，用清华 `ubuntu-ports` 装 `ubuntu-desktop-minimal`，然后切 `graphical.target` + GDM。
3. Linux 7.0 `boot.img` 的 initramfs 会在 `switch_root` 时把 overlay 拷进 userdata。

## 怎么试

**不必先擦 userdata。** 只换 boot（建议先 `fastboot boot`）：

```bash
# 先试启动，不要 flash。若卡死：长按电源回到 6.1。
fastboot boot out/boot.img
# 或刷入：
./scripts/flash-boot.sh
```

7.0 起来后 USB 串口 / RNDIS（`./scripts/usb-connect.sh`）。Wi-Fi 连上之后会开始 `apt install`（大约 1–2 GB，可能十几分钟）。日志：`/var/log/gemini-gnome-setup.log`。要从 Ubuntu 再进 fastboot 试下一枪：机上 `reboot-fastboot`，或电脑 `./scripts/reboot-fastboot.sh`。

也可以现在进 TWRP，提前把 overlay 灌进 6.1（下次 6.1 开机也会装 GNOME）：

```bash
# 小米 5：电源 + 音量加 → TWRP
./scripts/push-gnome-via-recovery.sh
```

## 预期

- 自动登录用户 `umeko`
- 屏 1080×1920，缩放 2
- 3D 走 Mesa `msm` / freedreno（Adreno 530）。若合成失败，先看 `journalctl -u gdm` 里有没有 `egl: failed to create dri2 screen`。
