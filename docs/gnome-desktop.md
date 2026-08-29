**Language:** English | [简体中文](zh-CN/gnome-desktop.md)

# GNOME on gemini

Overlay prepares GDM autologin, Wayland, modesetting+glamor, scale 2, on-screen keyboard, no idle lock. **GDM stays masked** while the HUD owns MSM scanout; unmasking it blacks the panel.

This is not the default UI. Flash/boot still starts `display-unblank` → `gemini-status`.
