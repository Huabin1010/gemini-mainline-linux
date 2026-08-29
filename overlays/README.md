# Device tree overlays

**Language:** English | [简体中文](README.zh-CN.md)

`scripts/apply-overlays.sh` copies these into `linux/` at build time:

- `msm8996-xiaomi-gemini-local.dtsi` — local dump / umeko / msm8996-mainline bits (`board-id` 31+32, UART stdout, 3000 mAh battery)
- `drivers/power/supply/qcom_fg.c` + `qcom-smbchg.c` — PMI8994 fuel gauge / charger (not in 7.0 mainline)

Upstream `msm8996-xiaomi-gemini.dts` stays vanilla 7.0 except a trailing `#include` of the local dtsi.
