#!/usr/bin/env python3
"""Keep a visible test pattern on /dev/fb0 and reboot-fastboot on Volume Up.

GDM/gnome-shell currently blacks the panel after a successful modeset, so this
runs instead of the display manager.
"""
import fcntl
import mmap
import os
import select
import struct
import sys
import time

LOG = "/var/log/gemini-display.log"
FBIOGET_VSCREENINFO = 0x4600
FBIOGET_FSCREENINFO = 0x4602
FBIOBLANK = 0x4611
EV_KEY = 1
EV_SYN = 0
KEY_VOLUMEUP = 115
INPUT_EVENT = struct.Struct("llHHi")  # timeval + type + code + value


def log(msg):
    ts = time.strftime("%Y-%m-%dT%H:%M:%S")
    line = "%s fb-ui: %s\n" % (ts, msg)
    try:
        with open(LOG, "a") as f:
            f.write(line)
    except OSError:
        pass
    sys.stderr.write(line)


def wait_fb(timeout=40):
    end = time.time() + timeout
    while time.time() < end:
        if os.path.exists("/dev/fb0"):
            return True
        time.sleep(0.2)
    return False


def pixel_bytes(var):
    (
        xres,
        yres,
        _xv,
        _yv,
        _xo,
        _yo,
        bpp,
        _gs,
        r_off,
        r_len,
        _r_msb,
        g_off,
        g_len,
        _g_msb,
        b_off,
        b_len,
        _b_msb,
    ) = var[:17]
    bytes_pp = max(1, (bpp + 7) // 8)
    # Bright green in the reported bitfields.
    g = (1 << g_len) - 1 if g_len else 0
    r = (1 << r_len) - 1 if r_len and g_len == 0 else 0
    val = (r << r_off) | (g << g_off)
    if not g_len and not r_len:
        val = 0x00FF00 if bpp > 16 else 0x07E0
    return val.to_bytes(bytes_pp, "little"), xres, yres, bpp, bytes_pp


def fill_fb():
    fd = os.open("/dev/fb0", os.O_RDWR)
    try:
        fcntl.ioctl(fd, FBIOBLANK, 0)
        var = array_u32(160)
        fcntl.ioctl(fd, FBIOGET_VSCREENINFO, var)
        fields = struct.unpack_from("I" * 20, var, 0)
        px, xres, yres, bpp, _bppb = pixel_bytes(fields)
        fix = bytearray(128)
        line = 0
        smem = 0
        try:
            fcntl.ioctl(fd, FBIOGET_FSCREENINFO, fix)
            # id[16], smem_start(8), smem_len(4), type, type_aux, visual,
            # xpan(2), ypan(2), ywrap(2), pad(2), line_length(4)
            smem = struct.unpack_from("I", fix, 24)[0]
            line = struct.unpack_from("I", fix, 48)[0]
        except OSError:
            pass
        if line <= 0:
            line = xres * len(px)
        if smem <= 0:
            smem = line * yres
        log(
            "fb %dx%d bpp=%d line=%d smem=%d px=%s"
            % (xres, yres, bpp, line, smem, px.hex())
        )
        row = (px * xres)[:line].ljust(line, b"\x00")
        blob = row * yres
        if len(blob) > smem > 0:
            blob = blob[:smem]
        # write() already produced visible pixels (the purple half-screen).
        written = 0
        while written < len(blob):
            n = os.write(fd, blob[written : written + 1024 * 1024])
            if n <= 0:
                break
            written += n
        os.lseek(fd, 0, os.SEEK_SET)
        try:
            mm = mmap.mmap(fd, smem, mmap.MAP_SHARED, mmap.PROT_WRITE | mmap.PROT_READ)
            try:
                mm[: len(blob)] = blob[: mm.size()]
            finally:
                mm.close()
        except OSError as e:
            log("mmap skip: %s" % e)
        os.fsync(fd)
        log("filled %d bytes" % written)
    finally:
        os.close(fd)


def array_u32(n):
    return bytearray(n)


def input_devs():
    devs = []
    base = "/sys/class/input"
    try:
        names = os.listdir(base)
    except OSError:
        return ["/dev/input/event0"]
    for n in names:
        if not n.startswith("event"):
            continue
        path = "/dev/input/" + n
        if os.path.exists(path):
            devs.append(path)
    return devs or ["/dev/input/event0"]


def listen_volume_up():
    fds = []
    for p in input_devs():
        try:
            fds.append(os.open(p, os.O_RDONLY | os.O_NONBLOCK))
        except OSError:
            continue
    if not fds:
        log("no input devices")
        while True:
            time.sleep(30)
    log("watching %d input nodes, Volume Up = reboot-fastboot" % len(fds))
    while True:
        r, _, _ = select.select(fds, [], [], 5.0)
        for fd in r:
            try:
                data = os.read(fd, INPUT_EVENT.size * 32)
            except OSError:
                continue
            for off in range(0, len(data) - INPUT_EVENT.size + 1, INPUT_EVENT.size):
                _s, _us, typ, code, value = INPUT_EVENT.unpack_from(data, off)
                if typ == EV_KEY and code == KEY_VOLUMEUP and value == 1:
                    log("Volume Up -> reboot-fastboot")
                    os.execv(
                        "/usr/local/sbin/reboot-fastboot",
                        ["reboot-fastboot"],
                    )


def main():
    if not wait_fb():
        log("no /dev/fb0")
        return 1
    last_err = None
    for i in range(8):
        try:
            fill_fb()
            last_err = None
            break
        except Exception as e:
            last_err = e
            log("fill try %d: %s" % (i, e))
            time.sleep(0.5)
    if last_err:
        log("fill failed: %s" % last_err)
    # Re-paint a few times in case a racing client blacks the plane.
    end = time.time() + 20
    while time.time() < end:
        time.sleep(2)
        try:
            fill_fb()
        except Exception as e:
            log("refill: %s" % e)
    listen_volume_up()
    return 0


if __name__ == "__main__":
    sys.exit(main())
