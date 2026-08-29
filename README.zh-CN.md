# gemini-mainline-linux

**语言：** [English](README.md) | 简体中文

小米 **Mi 5**（代号 **gemini**，高通 **MSM8996 / Snapdragon 820**）的主线 Linux 适配仓库。

本仓库编译 Linux 7.0 + Ubuntu 26.04 arm64 rootfs，并刷到手机上。这 **不是** AOSP。`system` 分区里还留着 LineageOS 17.1，启动不走 Android 用户空间。Ubuntu 在 **userdata** 上。日常更新内核只刷 **boot**。

测试机上：GLES HUD（Wi-Fi、亮度、中英、CPU/GPU/内存、上下行），GDM 保持 mask，避免 gnome-shell 冲黑扫描。

| 阶段 | 目标 | 状态 |
|------|------|------|
| P0 | 设备盘点 + 上游调研 | 完成 |
| P1 | Linux 7.0 + `boot.img` | 完成 |
| P2 | UFS rootfs + USB 串口 | 完成（`g_serial` ACM `0525:a4a7`） |
| P3 | DRM / JDI R63452 显示 | 完成（XRGB8888 fbdev；HUD 占屏） |
| P4 | 触控 Synaptics S3330 | HUD 点选 / 拖动可用 |
| P5 | Wi-Fi QCA6174（`ath10k_pci`） | HUD 扫描 + NetworkManager |
| P6 | GPU Adreno 530 | GLES 3.1 / freedreno FD530；HUD 优先 GBM/GLES2 |
| P7 | GNOME | overlay 在；GDM mask（会冲黑扫描） |
| P8 | 系统内进 LK | HUD 上短按 **音量加** → USB `18d1:d00d` |

**刷 Release 镜像：** [中文教程](docs/zh-CN/flash-guide.md) · [English](docs/flash-guide.md)

硬件说明和 bring-up 记录在 [`docs/zh-CN/`](docs/zh-CN/README.md)。英文默认文档在 [`docs/`](docs/README.md)。

## 这不是 ginkgo

旁边的 [ginkgo-mainline-linux](https://github.com/Huabin1010/ginkgo-mainline-linux) 是 Redmi Note 8（SM6125，ABL）。**不要**把 ginkgo 的 `dtbo` / `vbmeta` 刷到 gemini。小米 5 走 **LK**，DTB 打在 `boot.img` 里，没有空 dtbo 步骤。

## 快速开始

```bash
./scripts/setup-deps.sh
./scripts/setup-kernel.sh
./scripts/build-kernel.sh
./scripts/build-bootimg.sh
```

进了 LK（USB `18d1:d00d`）之后日常只：

```bash
fastboot flash boot out/boot.img && fastboot reboot
```

第一次把 Ubuntu 装到 userdata 才刷 rootfs，见 [刷机教程](docs/zh-CN/flash-guide.md)。

仓库里 **没有** root 密码。放到 gitignore 的 `rootfs-overlay/etc/gemini-root-password`（可参考 `.example`），或导出 `GEMINI_ROOT_PASSWORD`。

内核源码（`linux/`）和编译产物（`out/`）不进 git。

## 文档

| 主题 | 中文 | English |
|------|------|---------|
| 刷 Release | [刷机教程](docs/zh-CN/flash-guide.md) | [flash guide](docs/flash-guide.md) |
| 目录 | [docs/zh-CN/README.md](docs/zh-CN/README.md) | [docs/README.md](docs/README.md) |
| 机上实际在跑什么 | [做了什么](docs/zh-CN/what-we-built.md) | [English](docs/what-we-built.md) |

## 许可证

本仓库的构建脚本和原创文档是 [GPL-2.0-only](LICENSE)，与 Linux 内核相同。设备固件 blob 是专有的，仅供在抽出它们的那台设备上跑 Linux。
