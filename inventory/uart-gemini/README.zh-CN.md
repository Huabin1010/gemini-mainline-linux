**语言：** [English](README.md) | 简体中文

# 小米 5（gemini）调试串口

公开能用的点位来自 XDA：[Activating UART mode](https://xdaforums.com/t/activating-uart-mode.3834560/)（davidcie，2018），并与官方 ISL54062 **µTQFN** 脚位、小米原理图对得上。

XDA 附件原图因论坛 403 下不下来。本目录是拆机主板图 + 芯片手册脚位 + 按下表标好的焊盘图。

## 要焊哪两个口

热风揭开射频/音频屏蔽罩后，找 **没贴芯片的** 1.8×1.4 mm 十脚空位（原理图 `U711` / ISL54062）。量产板这颗开关是空贴。

| 焊盘 | 芯片脚 | 信号 | 接到 USB-TTL |
|------|--------|------|----------------|
| **5** | NO2 | 手机 **TX**（`MSM_UART_TX` / GPIO4） | 转接板 **RX** |
| **8** | NO1 | 手机 **RX**（`MSM_UART_RX` / GPIO5） | 转接板 **TX**（只看日志可以不焊） |
| **1** | GND | 地 | **GND**（必须共地） |

看图：`gemini-uart-isl54062-pads.png`（本目录），脚位对照 `ISL54062-pinout-p2-02.png`。

只抓启动日志：焊 **5 + GND** 就够。

## 参数

- **1.8 V** 电平（不是 3.3 V/5 V，没有电平转换容易把 SoC 口打坏）
- **115200 8N1**，无流控
- 内核真正的调试 UART 是 `blsp2_uart2` @ `0x075b0000`（GPIO4/5），**不是**蓝牙那根 `0x07570000`

## 不要焊的点

`photos/DO-NOT-USE-edl-testpoints.jpg` 是 **EDL 短接点**（刷机 9008），不是串口。

## 文件

| 文件 | 内容 |
|------|------|
| `gemini-uart-isl54062-pads.png` | 空贴焊盘 5=TX、8=RX |
| `ISL54062-datasheet.pdf` | Renesas 手册 |
| `ISL54062-pinout-p2-02.png` | 手册第 2 页脚位（用 µTQFN，不要用 3×3 TDFN） |
| `photos/myfixguide-teardown-10.webp` | 主板 + 屏蔽罩位置（ZEALER / MyFixGuide） |
| `photos/DO-NOT-USE-edl-testpoints.jpg` | EDL，勿当串口 |

主板拆机原图：https://www.myfixguide.com/manual/xiaomi-mi5-teardown/
