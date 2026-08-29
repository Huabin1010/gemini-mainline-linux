# gemini firmware

**Language:** English | [简体中文](README.zh-CN.md)

Copied from the device `/lib/firmware/qcom/msm8996/gemini/`. **Do not commit large blobs** (see `.gitignore`).

| File | Use |
|------|-----|
| `a530_zap.mbn` (and b00/b01/b02/mdt) | Adreno 530 zap |
| `venus.mbn` | Video |
| `mba.mbn` + `modem.mbn` | Modem PIL |
| `slpi.mbn` | Sensors |
| `adsp.mbn` | ADSP (often missing on-device; extract from modem/vendor if needed) |

Wi-Fi firmware lives under `ath10k/` for **QCA6174 PCI**, not WCN3990/SNOC.

Example (userdata mounted in TWRP):

```bash
adb pull /data/usr/lib/firmware/qcom/msm8996/gemini firmware/gemini/
```
