# 设备树 overlay

**语言：** [English](README.md) | 简体中文

编译时由 `scripts/apply-overlays.sh` 拷进 `linux/`：

- `msm8996-xiaomi-gemini-local.dtsi` — dump / umeko / msm8996-mainline 的本地补丁（`board-id` 31+32、UART stdout、3000 mAh 电池）
- `drivers/power/supply/qcom_fg.c` + `qcom-smbchg.c` — PMI8994 电量计 / 充电器（7.0 主线没有）

上游 `msm8996-xiaomi-gemini.dts` 保持 7.0 原版，只在文件末尾 `#include` 这份 local dtsi。
