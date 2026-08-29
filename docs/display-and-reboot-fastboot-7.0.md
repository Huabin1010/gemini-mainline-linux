**Language:** English | [简体中文](zh-CN/display-and-reboot-fastboot-7.0.md)

# Display scanout and in-OS reboot-fastboot (2026-08-28)

JDI R63452 command-mode panel, XRGB8888 fbdev. HUD owns `/dev/fb0` (or GBM/GLES2). GDM stays masked.

`display-unblank.service` must be **Type=simple** and stay running so Volume keys are heard. Short **Volume Up** (no Power) issues `SYS_reboot(..., "bootloader")`. Success is USB `18d1:d00d`. A black screen is not LK.

Do not start GDM from that oneshot. Do not type reboot into ACM.
