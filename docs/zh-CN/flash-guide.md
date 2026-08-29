**语言：** [English](../flash-guide.md) | 简体中文

# 刷机教程（小米 5 / gemini）

只适用于 **小米 5**（代号 **gemini**，MSM8996）。不要刷到别的机型。不要把 [ginkgo](https://github.com/Huabin1010/ginkgo-mainline-linux) 的 `dtbo` / `vbmeta` 刷到这台机上。

需要 **已解锁** 的 bootloader。刷 **userdata** 会清掉该分区上的 Android 和全部数据。

小米 5 用的是 **LK**，不是 ABL。设备树打在 `boot.img` 里。 **没有** 空 `dtbo` 这一步。

## 下载什么

GitHub [Release](https://github.com/Huabin1010/gemini-mainline-linux/releases) 提供可刷镜像：

| 文件 | 刷到 | 说明 |
|------|------|------|
| `boot.img` | `boot` | Linux 7.0 + DTB + initramfs overlay（HUD） |
| `rootfs.ext4.zst` | 解压后刷 `userdata` | GitHub 拒收裸的 2 GiB `rootfs.ext4`。**会清空 userdata。** |
| `SHA256SUMS` | — | 刷之前校验 |

Release 里的 rootfs 是 **精简 Ubuntu 26.04**，不是完整 GNOME 桌面。第一次开机请 `passwd`。本地可用 `scripts/build-rootfs.sh` 编更新的镜像。

请自己备份以前的 `boot.img`（TWRP 抽出的文件 gitignore）。

第一次安装：解压 rootfs，刷 userdata，再刷 `boot`。以后只更新内核就只刷 **boot**。

## 主机工具

```bash
sudo apt install android-sdk-platform-tools zstd
# 或:  export PATH="$HOME/.local/bin:$PATH"
```

确认解锁：

```bash
fastboot devices
fastboot getvar unlocked          # 应为 yes
fastboot getvar product           # 必须是 gemini
```

`product` 不是 `gemini` 就停手。

进 LK：关机后 **音量减 + 电源**，或在 HUD 上短按 **音量加**。成功时 USB 是 **`18d1:d00d`**。黑屏或 gadget 串口（`0525:a4a7`）上出现 FASTBOOT 字样 **都不是** LK。

## 第一次安装（清空 userdata）

下载 Release（示例 tag `v0.1.0`）：

```bash
gh release download v0.1.0 --repo Huabin1010/gemini-mainline-linux --dir out
cd out && sha256sum -c SHA256SUMS
zstd -d -f rootfs.ext4.zst
```

或自己在电脑上编 rootfs：

```bash
git clone https://github.com/Huabin1010/gemini-mainline-linux.git
cd gemini-mainline-linux
./scripts/setup-deps.sh
cp rootfs-overlay/etc/gemini-root-password.example rootfs-overlay/etc/gemini-root-password
# 改这个文件，然后：
chmod 600 rootfs-overlay/etc/gemini-root-password
./scripts/build-rootfs.sh
./scripts/configure-rootfs.sh
./scripts/build-rootfs-image.sh
```

然后：

```bash
export PATH="$HOME/.local/bin:$PATH"

# 1. Ubuntu → userdata（擦除该分区）
fastboot flash userdata out/rootfs.ext4

# 2. 主线内核 + HUD
fastboot flash boot out/boot.img

fastboot reboot
```

## 只更新内核（保留 Ubuntu）

手机已经在跑这份 rootfs，只想换内核或 HUD：

```bash
fastboot flash boot boot.img
fastboot reboot
```

除非打算清空系统，否则不要再刷 userdata。

在 Ubuntu 里可在 HUD 短按音量加进 LK，或执行 `reboot-fastboot`，再从电脑刷。

不刷机的热替换：`systemctl stop display-unblank.service`，把新的 `gemini-status` 和 `gemini-wifi-connect.sh` 拷到 `/usr/local/sbin/`，再启动服务。重启后 initramfs overlay 会盖回去，除非已经刷了新的 `boot.img`。

## 开机之后

USB 串口：主机 `/dev/ttyACM0`，gadget `0525:a4a7`。Release 里的 rootfs 已锁定密码哈希；USB 串口自动登录仍可进 shell。用密码走 SSH 之前请先 `passwd`。

SSH 可能在 USB RNDIS（`root@192.168.7.2`），或在 HUD 连上 Wi-Fi 之后的局域网地址。仓库里 **没有** root 密码。

## 救回旧内核

需要刷 Linux **之前** 备份的 `boot.img`。本仓库示例（文件 gitignore）：

```bash
fastboot flash boot inventory/boot-backup/boot-umeko-6.1.14-from-twrp.img
fastboot reboot
```

userdata 里如果已经是 Ubuntu，要不要清空是另一件事。

## 不要

- 把这些镜像刷到非 gemini 设备
- 把 ginkgo 的 `dtbo` / `vbmeta` 刷到 gemini
- 把密码放进公开 Release
- 只为更新 HUD 再刷一次 userdata
- 往 USB 串口里打 `reboot-fastboot`（会和 getty 抢）

## 发布 Release（维护者）

```bash
gh auth login
./scripts/build-bootimg.sh
./scripts/publish-release.sh v0.1.0
```

脚本会上传 `out/boot.img` 和 `SHA256SUMS`。只有存在 `out/rootfs-release.ext4`（由 `scripts/sanitize-rootfs-for-release.sh` 生成）时才会压成 `rootfs.ext4.zst` 一并上传。 **不会** 上传未脱敏的 `out/rootfs.ext4`，也 **不会** 上传 dtbo。
