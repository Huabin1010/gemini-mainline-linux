**语言：** [English](../reboot-fastboot.md) | 简体中文

# 从 Ubuntu 进 Fastboot（gemini）

机上脚本对内核发出 `reboot("bootloader")`（PON `mode-bootloader = <0x2>` + 复位），**不经过 systemd 关机**。7.0 上 GNOME/DRM 关屏之后可能永远到不了复位。

ginkgo 还靠 SoC DTB 里的 `qcom,pshold`。msm8996 没有这节点；加上 `pshold@4ab000` 或映射 IMEM（开机 syscon，或重启时 `/dev/mem`）都会把这台机卡死。

**不要**用这个命令覆盖 6.1 boot。进 fastboot 之后默认 `fastboot boot out/boot.img`。

判断是否进去：USB **`18d1:d00d`**。屏黑、屏上 FASTBOOT 字、USB 仍是 `0525:a4a7` 都不算。

## 机上

点桌面 **「重启到 Fastboot」**，或：

```text
reboot-fastboot
```

`umeko` 免密。`/etc/sudoers.d` 必须是 `root:root`、目录 `755`。

**不要**从电脑往 `/dev/ttyACM0` 打这条命令（和 getty 抢字，还可能把屏弄黑）。

## 电脑上

```bash
./scripts/reboot-fastboot.sh
fastboot boot out/boot.img
```

按键：关机后 **音量− + 电源**。TWRP：关机后 **电源 + 音量+**。
