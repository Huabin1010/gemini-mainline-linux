# Xiaomi Mi 5 (gemini) debug UART

**Language:** English | [简体中文](README.zh-CN.md)

Public pad map from XDA: [Activating UART mode](https://xdaforums.com/t/activating-uart-mode.3834560/) (davidcie, 2018). It matches the ISL54062 µTQFN pinout and the Xiaomi schematic.

The original XDA attachment is 403. This folder has a teardown photo, the datasheet pinout, and a labelled pad overlay.

## Which pads to solder

After hot-air removal of the RF/audio shield, find the unpopulated 1.8×1.4 mm 10-pin footprint (schematic `U711` / ISL54062). Production boards leave this analog switch unpopulated.

| Pad | Chip pin | Signal | USB-TTL adapter |
|-----|----------|--------|-----------------|
| **5** | NO2 | Phone **TX** (`MSM_UART_TX` / GPIO4) | Adapter **RX** |
| **8** | NO1 | Phone **RX** (`MSM_UART_RX` / GPIO5) | Adapter **TX** (optional if you only read logs) |
| **1** | GND | Ground | **GND** (required) |

Pictures: `gemini-uart-isl54062-pads.png` in this folder; pinout `ISL54062-pinout-p2-02.png`.

Boot log only: solder **5 + GND**.

## Settings

- **1.8 V** logic (not 3.3 V / 5 V; no level shifter can damage the SoC pin)
- **115200 8N1**, no flow control
- Kernel debug UART is `blsp2_uart2` @ `0x075b0000` (GPIO4/5), **not** the Bluetooth UART at `0x07570000`

## Do not solder these

`photos/DO-NOT-USE-edl-testpoints.jpg` is the **EDL** short (9008), not UART.

## Files

| File | Contents |
|------|----------|
| `gemini-uart-isl54062-pads.png` | Empty footprint: pad 5=TX, 8=RX |
| `ISL54062-datasheet.pdf` | Renesas datasheet |
| `ISL54062-pinout-p2-02.png` | Page 2 pinout (use µTQFN, not 3×3 TDFN) |
| `photos/myfixguide-teardown-10.webp` | Board + shield location (ZEALER / MyFixGuide) |
| `photos/DO-NOT-USE-edl-testpoints.jpg` | EDL; not UART |

Teardown source: https://www.myfixguide.com/manual/xiaomi-mi5-teardown/
