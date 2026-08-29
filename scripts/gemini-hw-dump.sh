#!/bin/bash
# Collect live hardware inventory on Xiaomi Mi 5 (gemini) Ubuntu.
# Intended to run as root after boot (oneshot) or manually.
set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${1:-/root/hw-dump/${STAMP}}"
mkdir -p "$OUT"

log() { echo "[hw-dump] $*" | tee -a "$OUT/00-summary.txt"; }

{
	echo "stamp=$STAMP"
	echo "hostname=$(hostname 2>/dev/null || true)"
	uname -a
} > "$OUT/00-summary.txt"

log "collecting..."

uname -a > "$OUT/uname.txt" 2>&1 || true
cat /proc/cmdline > "$OUT/cmdline.txt" 2>/dev/null || true
cat /proc/cpuinfo > "$OUT/cpuinfo.txt" 2>/dev/null || true
cat /proc/meminfo > "$OUT/meminfo.txt" 2>/dev/null || true
cat /proc/version > "$OUT/version.txt" 2>/dev/null || true
cat /etc/os-release > "$OUT/os-release.txt" 2>/dev/null || true
dmesg > "$OUT/dmesg.txt" 2>/dev/null || true
lsmod > "$OUT/lsmod.txt" 2>/dev/null || true
mount > "$OUT/mounts.txt" 2>/dev/null || true
df -h > "$OUT/df.txt" 2>/dev/null || true
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINT > "$OUT/lsblk.txt" 2>/dev/null || true
blkid > "$OUT/blkid.txt" 2>/dev/null || true
cat /proc/partitions > "$OUT/partitions.txt" 2>/dev/null || true

ip -br link > "$OUT/ip-link.txt" 2>/dev/null || true
ip -br addr > "$OUT/ip-addr.txt" 2>/dev/null || true
ip route > "$OUT/ip-route.txt" 2>/dev/null || true
iw dev > "$OUT/iw-dev.txt" 2>/dev/null || true
iw list > "$OUT/iw-list.txt" 2>/dev/null || true
nmcli -t dev > "$OUT/nmcli-dev.txt" 2>/dev/null || true
nmcli -t con show --active > "$OUT/nmcli-active.txt" 2>/dev/null || true

ls -l /dev/dri /dev/fb* /dev/input /dev/ttyMSM* /dev/ttyGS* /dev/disk/by-partlabel 2>"$OUT/dev-ls.err" | tee "$OUT/dev-ls.txt" >/dev/null || true
cat /sys/class/drm/*/status > "$OUT/drm-status.txt" 2>/dev/null || true
for n in /sys/class/drm/*/modes; do
	echo "== $n =="; cat "$n" 2>/dev/null || true
done > "$OUT/drm-modes.txt" 2>/dev/null || true

cat /sys/class/power_supply/*/uevent > "$OUT/power_supply.txt" 2>/dev/null || true
cat /sys/class/thermal/thermal_zone*/type /sys/class/thermal/thermal_zone*/temp > "$OUT/thermal.txt" 2>/dev/null || true
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq > "$OUT/cpufreq.txt" 2>/dev/null || true
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_available_frequencies > "$OUT/cpufreq-avail.txt" 2>/dev/null || true

find /sys/firmware/devicetree/base -name compatible -print -exec cat {} \; > "$OUT/dt-compatible.txt" 2>/dev/null || true
cat /proc/device-tree/model > "$OUT/dt-model.txt" 2>/dev/null || true
cat /proc/device-tree/compatible > "$OUT/dt-root-compatible.txt" 2>/dev/null || true
if command -v dtc >/dev/null; then
	dtc -I fs -O dts /sys/firmware/devicetree/base > "$OUT/live.dts" 2>/dev/null || true
fi

ls -l /lib/firmware/qcom/msm8996/gemini /lib/firmware/ath10k 2>"$OUT/firmware.err" | tee "$OUT/firmware-ls.txt" >/dev/null || true
journalctl -b -o short-precise > "$OUT/journal-boot.txt" 2>/dev/null || true

log "done -> $OUT"
echo "$OUT" > /root/hw-dump/LATEST
# also copy a pointer for the umeko user if present
if [[ -d /home/umeko ]]; then
	cp -a "$OUT/00-summary.txt" /home/umeko/hw-dump-LATEST.txt 2>/dev/null || true
	chown 1000:1000 /home/umeko/hw-dump-LATEST.txt 2>/dev/null || true
fi
