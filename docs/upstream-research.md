**Language:** English | [简体中文](zh-CN/upstream-research.md)

# Upstream research (2026-08-27)

Goal: move gemini from `6.1.14-umeko-rv0` to Linux **7.0**.

Mainline already has `arch/arm64/boot/dts/qcom/msm8996-xiaomi-gemini.dts` (`xiaomi,gemini`, `qcom,msm8996`). Panel `jdi,fhd-r63452`, touch `syna,rmi4-i2c@20`, GPU zap `qcom/msm8996/gemini/a530_zap.mbn`.

The 6.1 umeko version string matches msm8996-mainline tag `v6.1.14-msm8996`. Linux 7.0 from torvalds already includes the gemini DTS. Local changes stay in `overlays/` and are `#include`d, not patched into upstream files.
