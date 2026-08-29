#!/usr/bin/env bash
# Host side: wait for gemini USB RNDIS (192.168.7.2) and/or ACM serial.
set -euo pipefail

HOST_IP="${HOST_IP:-192.168.7.1/24}"
PHONE_IP="${PHONE_IP:-192.168.7.2}"
SSH_USER="${SSH_USER:-root}"
SERIAL="${SERIAL:-/dev/ttyACM0}"

echo "==> USB"
lsusb | grep -iE '1d6b|0525|xiaomi|gadget|rndis' || lsusb
ls -l /dev/ttyACM* 2>/dev/null || true

iface=""
for _ in $(seq 1 45); do
	for cand in /sys/class/net/*; do
		name=$(basename "$cand")
		[[ "$name" == lo ]] && continue
		driver=$(readlink -f "$cand/device/driver" 2>/dev/null || true)
		if [[ "$driver" == *rndis* ]] || [[ "$driver" == *cdc_ether* ]] || [[ "$name" == enx* ]] || [[ "$name" == usb0 ]]; then
			iface=$name
			break 2
		fi
	done
	sleep 1
done

if [[ -z "$iface" ]]; then
	echo "warn: no RNDIS yet (serial gadget may still be up)"
	ip -br link || true
	exit 0
fi

echo "==> RNDIS $iface"
if command -v nmcli &>/dev/null; then
	sudo nmcli device set "$iface" managed no || true
	sudo nmcli device disconnect "$iface" || true
fi
sudo ip link set "$iface" up
sudo ip addr flush dev "$iface" 2>/dev/null || true
sudo ip addr add "$HOST_IP" dev "$iface"
sudo ip route replace "${PHONE_IP%.*}.0/24" dev "$iface" metric 500

HOST_ADDR="${HOST_IP%%/*}"
echo "==> Waiting for $PHONE_IP ..."
for _ in $(seq 1 30); do
	if ping -c1 -W1 -I "$HOST_ADDR" "$PHONE_IP" &>/dev/null; then
		echo "==> Ping OK"
		echo "SSH: ssh -b $HOST_ADDR ${SSH_USER}@${PHONE_IP}"
		exit 0
	fi
	sleep 1
done

echo "error: phone not responding on $PHONE_IP" >&2
exit 1
