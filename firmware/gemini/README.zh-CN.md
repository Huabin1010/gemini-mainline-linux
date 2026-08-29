# gemini 固件

**语言：** [English](README.md) | 简体中文

从真机 `/lib/firmware/qcom/msm8996/gemini/` 拷贝。**不要提交大 blob**（见 `.gitignore`）。

| 文件 | 用途 |
|------|------|
| `a530_zap.mbn`（及 b00/b01/b02/mdt） | Adreno 530 zap |
| `venus.mbn` | 视频 |
| `mba.mbn` + `modem.mbn` | 基带 PIL |
| `slpi.mbn` | 传感器核 |
| `adsp.mbn` | ADSP（机上目录里经常没有，要从 modem 分区或 vendor 抽） |

Wi-Fi 固件在 `ath10k/`，芯片是 **QCA6174 PCI**，不是 WCN3990/SNOC。

抽取示例（TWRP 已挂 userdata 时）：

```bash
adb pull /data/usr/lib/firmware/qcom/msm8996/gemini firmware/gemini/
```
