#!/usr/bin/env bash
# Wait for LK fastboot after the phone reboots into the bootloader.
# Do not write to USB ACM: opening ttyACM0 fights getty, garbles
# "reboot-fastboot", and can blank the panel while Ubuntu is still running.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAIT_SEC="${WAIT_SEC:-90}"
SSH_USER="${SSH_USER:-root}"
PHONE_IP="${PHONE_IP:-192.168.7.2}"
export PATH="$HOME/.local/bin:$PATH"

if fastboot devices 2>/dev/null | grep -q .; then
	echo "==> already in fastboot"
	fastboot devices
	exit 0
fi

try_ssh() {
	ping -c1 -W1 "$PHONE_IP" &>/dev/null || return 1
	echo "==> SSH $SSH_USER@$PHONE_IP reboot-fastboot"
	ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
		-o ConnectTimeout=8 "${SSH_USER}@${PHONE_IP}" \
		'command -v reboot-fastboot >/dev/null && reboot-fastboot || sudo -n reboot bootloader' \
		|| true
	return 0
}

if try_ssh; then
	:
else
	echo "==> Do not type reboot-fastboot into the USB serial console"
	echo "    (it races getty and can blank the panel while Ubuntu is still running)."
	echo "    Use the on-screen Fastboot control, or power off and hold Vol- + Power."
fi

echo "==> Waiting up to ${WAIT_SEC}s for USB 18d1:d00d (a black screen or FASTBOOT text is not enough)"
for ((i = 1; i <= WAIT_SEC; i++)); do
	if fastboot devices 2>/dev/null | grep -q .; then
		echo "==> fastboot OK (${i}s)"
		fastboot devices
		exit 0
	fi
	sleep 1
done

echo "error: no fastboot device after ${WAIT_SEC}s" >&2
echo "Keys: power off, then Vol- + Power. Success is lsusb 18d1:d00d, not 0525:a4a7." >&2
fastboot devices || true
lsusb | grep -iE '0525|18d1|d00d' || true
exit 1
