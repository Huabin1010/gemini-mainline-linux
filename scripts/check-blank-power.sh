#!/usr/bin/env bash
# Automated acceptance for "screen-off gates GPU + DSI/MDP".
# Exit 0 = task done. No visual inspection.
#
# Metrics (all sysfs / dmesg / FG):
#   OFF after 4s settle, 5 samples:
#     M1 GPU runtime_status=suspended
#     M2 DSI 994000.dsi runtime_status=suspended
#     M3 MDP 901000.display-controller runtime_status=suspended
#     M4 DSI PLL / MDP / GFX clocks enable_cnt=0
#     M4b median(P) <= 3.00 W (FG ±0.4 W; analog-keep + Wi-Fi. Hard gate is
#        clock enable_cnt=0. ~2.4 W was DSI-up blank; screen-on is ~3.3–3.8 W)
#   ON after unblank, 3s settle:
#     M5 panel_sleep is 0 and power_mode 0x38
#     M6 GPU runtime_status=active
#     M7 DSI runtime_status=active
#     M8 CRTC active=1
#     M9 /dev/input/event3 exists, 1s idle 0 bytes
#     M10 dmesg delta has no rmi_set_page failed / rcg didn't update
#     M11 median(P_on) >= 2.00 W and P_on - P_off >= 0.50 W
#     M12 analog-keep (white-bar proxy): 994400.phy stays active,
#         vcca/vddio stay enabled; resume log is DCS 0x29 no 0x11
set -euo pipefail

if [[ -f /sys/class/power_supply/qcom-battery/current_now ]]; then
	python3 - "$@" <<'PY'
import glob, mmap, os, struct, sys, time

P_OFF_MAX = 3.00
P_ON_MIN = 2.00
P_DELTA_MIN = 0.50
GPU = "/sys/devices/platform/soc@0/b00000.gpu/power/runtime_status"
DSI = "/sys/devices/platform/soc@0/900000.display-subsystem/994000.dsi/power/runtime_status"
MDP = "/sys/devices/platform/soc@0/900000.display-subsystem/901000.display-controller/power/runtime_status"
PHY = "/sys/devices/platform/soc@0/900000.display-subsystem/994400.phy/power/runtime_status"
PANEL = "/sys/bus/mipi-dsi/devices/994000.dsi.0/panel_sleep"
EV = "/dev/input/event3"
ANALOG_REGS = ("vreg_l28a_0p925", "vreg_l14a_1p8", "vreg_l19a_3p3")
CLK = "/sys/kernel/debug/clk/clk_summary"
FAIL = []

def rd(p):
    try:
        return open(p).read().strip()
    except Exception as e:
        return f"ERR:{e}"

def regulator_state(name):
    for p in glob.glob("/sys/class/regulator/regulator.*"):
        try:
            if open(os.path.join(p, "name")).read().strip() == name:
                return open(os.path.join(p, "state")).read().strip()
        except Exception:
            continue
    return "missing"

def phy_cmn_ctrl0():
    phy = 0x994400
    try:
        fd = os.open("/dev/mem", os.O_RDONLY)
        page = phy & ~0xFFF
        m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=page)
        os.close(fd)
        v = struct.unpack_from("<I", m, (phy - page) + 0x1C)[0]
        m.close()
        return v
    except Exception:
        return None

def watts():
    ua = int(open("/sys/class/power_supply/qcom-battery/current_now").read())
    uv = int(open("/sys/class/power_supply/qcom-battery/voltage_now").read())
    return abs(ua) * uv / 1e12

def median(xs):
    xs = sorted(xs)
    n = len(xs)
    return xs[n // 2] if n else None

def sample_p(n, gap):
    xs = []
    for _ in range(n):
        xs.append(watts())
        time.sleep(gap)
    return xs

def key_power():
    fd = os.open("/dev/input/event0", os.O_WRONLY)
    def ev(t, c, v):
        now = time.time()
        sec = int(now)
        usec = int((now - sec) * 1e6)
        os.write(fd, struct.pack("llHHi", sec, usec, t, c, v))
    ev(1, 116, 1); ev(0, 0, 0)
    time.sleep(0.05)
    ev(1, 116, 0); ev(0, 0, 0)
    os.close(fd)

def panel_asleep():
    s = rd(PANEL)
    return s.startswith("1 ")

def clk_enable(name):
    try:
        t = open(CLK).read()
    except Exception:
        return None
    for line in t.splitlines():
        if name not in line:
            continue
        parts = line.split()
        for i, p in enumerate(parts):
            if p == name:
                try:
                    return int(parts[i + 1])
                except Exception:
                    return None
    return None

def ensure_on():
    if not panel_asleep():
        return
    key_power()
    for _ in range(20):
        time.sleep(0.2)
        if not panel_asleep():
            time.sleep(1.5)
            return
    FAIL.append("cannot unblank before test")

def crtc_active():
    try:
        t = open("/sys/kernel/debug/dri/0/state").read()
    except Exception:
        return False
    return ("\n\tactive=1" in t)

def idle_touch_bytes():
    if not os.path.exists(EV):
        return -1
    fd = os.open(EV, os.O_RDONLY | os.O_NONBLOCK)
    t0 = time.time()
    n = 0
    while time.time() - t0 < 1.0:
        try:
            n += len(os.read(fd, 4096))
        except BlockingIOError:
            time.sleep(0.05)
        except OSError:
            break
    os.close(fd)
    return n

def dmesg_tail():
    return os.popen("dmesg").read()[-8000:]

ensure_on()
time.sleep(2.0)
d0 = dmesg_tail()
p_on = sample_p(3, 0.7)
print(f"P_on samples={[round(x,2) for x in p_on]} med={median(p_on):.2f}")

key_power()
time.sleep(4.0)
if not panel_asleep() and "power=0/0x30" not in rd(PANEL):
    FAIL.append(f"OFF panel_sleep={rd(PANEL)} (want asleep)")

g, d, m = rd(GPU), rd(DSI), rd(MDP)
print(f"OFF gpu={g} dsi={d} mdp={m} panel={rd(PANEL)}")
if g != "suspended":
    FAIL.append(f"M1 GPU runtime={g} want suspended")
if d != "suspended":
    FAIL.append(f"M2 DSI runtime={d} want suspended")
if m != "suspended":
    FAIL.append(f"M3 MDP runtime={m} want suspended")

phy = rd(PHY)
print(f"OFF phy={phy}")
if phy != "active":
    FAIL.append(f"M12 PHY runtime={phy} want active (analog keep)")
for n in ANALOG_REGS:
    st = regulator_state(n)
    print(f"OFF {n}={st}")
    if st != "enabled":
        FAIL.append(f"M12 {n}={st} want enabled")
cmn = phy_cmn_ctrl0()
print(f"OFF PHY CMN_CTRL_0={None if cmn is None else hex(cmn)}")
if cmn is not None and cmn != 0xFF:
    FAIL.append(f"M12 PHY analog powered down CMN_CTRL_0={hex(cmn)} want 0xff")

for clk in ("dsi0vco_clk", "mdss_mdp_clk", "gpu_gx_gfx3d_clk"):
    en = clk_enable(clk)
    print(f"OFF clk {clk} enable={en}")
    if en is None:
        FAIL.append(f"M4 {clk} missing from clk_summary")
    elif en > 0:
        FAIL.append(f"M4 {clk} enable={en} want 0")

p_off = sample_p(5, 0.8)
print(f"P_off samples={[round(x,2) for x in p_off]} med={median(p_off):.2f}")
if median(p_off) is None or median(p_off) > P_OFF_MAX:
    FAIL.append(f"M4 P_off={median(p_off):.2f}W > {P_OFF_MAX:.2f}W")

key_power()
time.sleep(4.0)
ps = rd(PANEL)
print(f"ON panel={ps} gpu={rd(GPU)} dsi={rd(DSI)}")
if not (ps.startswith("0 ") and "0x38" in ps):
    FAIL.append(f"M5 panel_sleep={ps} want 0 ... 0x38")
if rd(GPU) != "active":
    FAIL.append(f"M6 GPU runtime={rd(GPU)} want active")
if rd(DSI) != "active":
    FAIL.append(f"M7 DSI runtime={rd(DSI)} want active")
if not crtc_active():
    FAIL.append("M8 CRTC active!=1")
tb = idle_touch_bytes()
print(f"idle touch bytes={tb}")
if tb != 0:
    FAIL.append(f"M9 event3 idle bytes={tb} (missing or ghost)")
delta = dmesg_tail()
if delta.count("rmi_set_page: set page failed") > d0.count("rmi_set_page: set page failed"):
    FAIL.append("M10 new rmi_set_page failure")
if d0.count("rcg didn't update") < delta.count("rcg didn't update"):
    FAIL.append("M10 new RCG update failure")
if "DCS 0x29, no 0x11" not in delta:
    FAIL.append("M12 resume log missing DCS 0x29 no 0x11")
if "enable resume (0x11" in delta:
    FAIL.append("M12 resume still sent DCS 0x11")

p_on2 = sample_p(3, 0.7)
print(f"P_on2 samples={[round(x,2) for x in p_on2]} med={median(p_on2):.2f}")
if median(p_on2) < P_ON_MIN:
    FAIL.append(f"M11 P_on={median(p_on2):.2f}W < {P_ON_MIN:.2f}W")
if median(p_on2) - median(p_off) < P_DELTA_MIN:
    FAIL.append(f"M11 delta={median(p_on2)-median(p_off):.2f}W < {P_DELTA_MIN:.2f}W")

if FAIL:
    print("FAIL")
    for f in FAIL:
        print(" -", f)
    sys.exit(1)
print("PASS")
sys.exit(0)
PY
	exit $?
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
PASSFILE="${PASSFILE:-$ROOT/rootfs-overlay/etc/gemini-root-password}"
PHONE_IP="${PHONE_IP:-192.168.1.130}"

[[ -f "$PASSFILE" ]] || { echo "missing $PASSFILE and not on-device" >&2; exit 2; }
exec sshpass -f "$PASSFILE" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 \
	"root@$PHONE_IP" "bash -s" < "$0"
