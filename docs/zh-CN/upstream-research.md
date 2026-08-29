**语言：** [English](../upstream-research.md) | 简体中文

# 上游与社区适配调研

记录时间：2026-08-27。目标：把 gemini 从 `6.1.14-umeko-rv0` 迁到 **Linux 7.0** 主线。

## 结论

小米 5 **已经在主线内核里**，设备树路径：

```text
arch/arm64/boot/dts/qcom/msm8996-xiaomi-gemini.dts
arch/arm64/boot/dts/qcom/msm8996-xiaomi-common.dtsi
```

compatible：`xiaomi,gemini`, `qcom,msm8996`。面板 `jdi,fhd-r63452`，触控 `syna,rmi4-i2c@20`，GPU zap `qcom/msm8996/gemini/a530_zap.mbn`。

这台机上的 `6.1.14-umeko-rv0` 版本号和 [msm8996-mainline](https://gitlab.com/msm8996-mainline/linux) 的 tag **`v6.1.14-msm8996`** 一致，基本可以认定 umeko 内核就是该树的定制包。

Linux 7.0 的 `torvalds` 树已经包含 gemini DTS。msm8996-mainline 自己还没有 7.0 分支（调研时最新 stable 是 **6.19.5-msm8996**，staging 默认分支 `msm8996-staging`）。

## 仓库对照

| 来源 | 地址 | 用途 |
|------|------|------|
| 主线 | https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git tag `v7.0` | 7.0 编译基线 |
| 主线 DTS | https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/msm8996-xiaomi-gemini.dts | 官方设备树 |
| 社区内核 | https://gitlab.com/msm8996-mainline/linux | 820 平台补丁；gemini 有 board-id 31 **和 32** |
| postmarketOS 设备包 | `device-xiaomi-gemini`（pkgs.postmarketos.org，维护者 cunidev / Raffaele Tranquillini） | 依赖 `linux-postmarketos-qcom-msm8996` |
| pmOS Wiki | https://wiki.postmarketos.org/wiki/Xiaomi_Mi_5_(xiaomi-gemini) | 硬件支持表（站点有反爬） |
| 杂项 | https://github.com/Virace/gemini-pmos-tweaks | pmOS 优化脚本，不是内核树 |

相关作者：

- Raffaele Tranquillini（cunidev）：gemini DTS 版权 / pmOS 设备维护
- Yassine Oudjana（Tooniis）：xiaomi-common、board-id 32
- Krzysztof Kozlowski：触控 VIO、UFS pad supply 等 DTS 修正

## 主线 DTS vs msm8996-staging（要点）

staging 比主线多/改了这些，7.0 适配时要对着看：

- `qcom,board-id = <31 0>, <32 0>;`（主线只有 31）
- 电池 `charge-full-design-microamp-hours = <3000000>`
- GPU 节点写成 `&gpu { zap-shader { ... } }`（主线仍是 `&gpu_zap_shader`）
- 声音节点简化成 `model = "gemini"`
- haptics `enable-gpio` 写法
- DSI sleep pinctrl：`mdss_te_sleep`

这台机 `hwversion=1.4.0`。若 LK 传的 board-id 是 32，主线只有 31 也可能仍能启动（DTB 是我们打进 boot.img 的，不靠 LK 按 board-id 选 DTB）。

## 现网内核 vs 上游缺口

| 功能 | 6.1 umeko 现网 | 主线 7.0 DTS/驱动 | 适配注意 |
|------|----------------|-------------------|----------|
| 启动 + UFS | 正常 | `SCSI_UFS_QCOM` | 必须 built-in |
| USB 串口 gadget | CDC ACM `/dev/ttyACM0` | configfs serial | 先保住这条调试通道 |
| 显示 | simplefb + JDI 面板模块 | `DRM_MSM` + `jdi,fhd-r63452` | 7.0 优先 DRM，不要只靠 simplefb |
| 触控 | 真机 Synaptics S3330 | `syna,rmi4-i2c` | 一致，7.0 沿用 |
| Wi-Fi | `ATH10K_PCI` QCA6174 hw3.2 `wlp1s0` | 不是 WCN3990/SNOC | 7.0 开 `ATH10K_PCI` |
| GPU | 固件在，Xorg 无 glamor | msm drm + zap | P6 |
| 基带/ADSP | 固件目录有 modem/slpi，未见 adsp.mbn | DTS 要 adsp.mbn | 缺文件会 PIL 失败 |

## 和 ginkgo 仓库的关系

`../Kernel-Build` 是 Redmi Note 8（SM6125）的 Linux 7.0 适配，流程可复用：`setup-kernel.sh` → fragment → `Image.gz` + DTB → `boot.img`。

gemini 差异：

- SoC 是 MSM8996，不是 SM6125；时钟/pinctrl/interconnect 符号都不同
- 存储是 **UFS** 不是 eMMC
- boot.img 是 **v0**（`0x80008000`），不是 ginkgo 的 header v2
- 已有可用 Ubuntu rootfs，第一刀只换内核

## 参考提交（历史）

- `4ac46b3682c5` arm64: dts: qcom: msm8996: xiaomi-gemini: Add support for Xiaomi Mi 5
- `21fc24ee9c59` msm8996-gemini: fix touchscreen VIO supply（vdda → vio）
- `38f6ac152fa6` msm8996-gemini: correct UFS pad supply
- msm8996-mainline: `arm64: dts: qcom: msm8996-xiaomi-gemini: Add second board-id`
