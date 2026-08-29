**Language:** English | [简体中文](zh-CN/reboot-fastboot.md)

# Reboot to LK from Ubuntu

On the HUD: short **Volume Up** only. Do not hold Power (that combo is the hardware key for LK after shutdown).

From a shell: `reboot-fastboot` (static helper) or `sudo reboot bootloader`. Success is USB `18d1:d00d`.

Do not paste that command into the USB serial console; it races getty and can blank the panel while the OS is still running. Host helper: `./scripts/reboot-fastboot.sh` (set `PHONE_IP` if you use Wi-Fi SSH).
