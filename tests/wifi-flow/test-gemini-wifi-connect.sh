#!/usr/bin/env bash
# Integration tests for gemini-wifi-connect.sh with a fake nmcli.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/rootfs-overlay/usr/local/sbin/gemini-wifi-connect.sh"
FAKE="$ROOT/tests/wifi-flow/fake-nmcli"
WORKDIR="${TMPDIR:-/tmp}/gemini-wifi-flow-$$"
mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT

fails=0
ok() { echo "ok  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

run_script() {
	local state="$1"
	shift
	FAKE_NM_STATE="$state" \
		NMCLI="$FAKE" \
		GEMINI_WIFI_LOG="$WORKDIR/wifi.log" \
		GEMINI_WIFI_WAIT=0 \
		TMPDIR="$WORKDIR" \
		"$SCRIPT" "$@"
}

run_capture() {
	set +e
	out=$(run_script "$@")
	ec=$?
	set -e
}

# --- already connected: empty pass must succeed, never NEED_PASSWORD
st="$WORKDIR/s1"
mkdir -p "$st"
echo uuid-home >"$st/active"
echo "HomeNet" >"$st/ssid.uuid-home"
echo wpa-psk >"$st/km.uuid-home"
echo 0 >"$st/flags.uuid-home"
echo secret >"$st/psk.uuid-home"
run_capture "$st" "HomeNet" "" "wlan0" "WPA2"
if [[ "$ec" -eq 0 && "$out" == *已连接* && "$out" != *NEED_PASSWORD* ]]; then
	ok "already-up empty pass"
else
	fail "already-up empty pass (ec=$ec out=$out)"
fi

# --- saved profile, psk hidden (nmcli -s prints nothing), flags 0 → still up
st="$WORKDIR/s2"
mkdir -p "$st"
echo "Cafe" >"$st/ssid.uuid-cafe"
echo wpa-psk >"$st/km.uuid-cafe"
echo 0 >"$st/flags.uuid-cafe"
echo secret >"$st/psk.uuid-cafe"
# no psk_visible file
run_capture "$st" "Cafe" "" "wlan0" "WPA2"
if [[ "$ec" -eq 0 && "$out" == *已连接* ]]; then
	ok "saved flags0 hidden psk"
else
	fail "saved flags0 hidden psk (ec=$ec out=$out)"
fi

# --- agent-owned flags=1, no pass → NEED_PASSWORD
st="$WORKDIR/s3"
mkdir -p "$st"
echo "Cafe" >"$st/ssid.uuid-cafe"
echo wpa-psk >"$st/km.uuid-cafe"
echo 1 >"$st/flags.uuid-cafe"
run_capture "$st" "Cafe" "" "wlan0" "WPA2"
if [[ "$ec" -eq 2 && "$out" == *NEED_PASSWORD* ]]; then
	ok "agent-owned needs password"
else
	fail "agent-owned needs password (ec=$ec out=$out)"
fi

# --- saved PSK is present but wrong (psk mismatch) → 密码不对, not a blank prompt
st="$WORKDIR/s3b"
mkdir -p "$st"
echo "Cafe" >"$st/ssid.uuid-cafe"
echo wpa-psk >"$st/km.uuid-cafe"
echo 0 >"$st/flags.uuid-cafe"
echo secret >"$st/psk.uuid-cafe"
touch "$st/psk_visible"
touch "$st/mismatch"
run_capture "$st" "Cafe" "" "wlan0" "WPA2"
if [[ "$ec" -eq 3 && "$out" == *密码不对* && "$out" != *NEED_PASSWORD* ]]; then
	ok "saved wrong psk reports 密码不对"
else
	fail "saved wrong psk reports 密码不对 (ec=$ec out=$out)"
fi

# --- typed password still mismatches → 密码不对 (never NEED_PASSWORD)
st="$WORKDIR/s3c"
mkdir -p "$st"
echo "Cafe" >"$st/ssid.uuid-cafe"
echo wpa-psk >"$st/km.uuid-cafe"
echo 0 >"$st/flags.uuid-cafe"
touch "$st/mismatch"
run_capture "$st" "Cafe" "wrong-password" "wlan0" "WPA2"
if [[ "$ec" -eq 3 && "$out" == *密码不对* && "$out" != *NEED_PASSWORD* ]]; then
	ok "typed wrong psk reports 密码不对"
else
	fail "typed wrong psk reports 密码不对 (ec=$ec out=$out)"
fi

# --- without passwd-file NM asks secrets; with passwd-file it joins
st="$WORKDIR/s3d"
mkdir -p "$st"
echo "Cafe" >"$st/ssid.uuid-cafe"
echo wpa-psk >"$st/km.uuid-cafe"
echo 0 >"$st/flags.uuid-cafe"
echo secret >"$st/psk.uuid-cafe"
touch "$st/psk_visible"
touch "$st/need_passwd_file"
run_capture "$st" "Cafe" "" "wlan0" "WPA2"
if [[ "$ec" -eq 0 && "$out" == *已连接* ]]; then
	ok "empty join uses passwd-file for saved psk"
else
	fail "empty join uses passwd-file for saved psk (ec=$ec out=$out)"
fi

# --- provide password: create profile and up
st="$WORKDIR/s4"
mkdir -p "$st"
run_capture "$st" "Cafe" "correct-password" "wlan0" "WPA2"
if [[ "$ec" -eq 0 && "$out" == *已连接* && -f "$st/ssid.Cafe" ]]; then
	ok "password create and up"
else
	fail "password create and up (ec=$ec out=$out)"
fi

# --- already saved profile: password updates in place, does not drop uuid
st="$WORKDIR/s4b"
mkdir -p "$st"
echo "Cafe" >"$st/ssid.uuid-cafe"
echo wpa-psk >"$st/km.uuid-cafe"
echo 2 >"$st/flags.uuid-cafe"
run_capture "$st" "Cafe" "correct-password" "wlan0" "WPA2"
flags=$(cat "$st/flags.uuid-cafe" 2>/dev/null || true)
if [[ "$ec" -eq 0 && "$out" == *已连接* && -f "$st/ssid.uuid-cafe" && "$flags" == 0 ]]; then
	ok "password modify in place"
else
	fail "password modify in place (ec=$ec out=$out flags=$flags)"
fi

# --- old log secrets must not leak into a successful run
st="$WORKDIR/s5"
mkdir -p "$st"
echo "Cafe" >"$st/ssid.uuid-cafe"
echo wpa-psk >"$st/km.uuid-cafe"
echo 0 >"$st/flags.uuid-cafe"
echo "Error: Secrets were required, but not provided." >"$WORKDIR/wifi.log"
run_capture "$st" "Cafe" "" "wlan0" "WPA2"
if [[ "$ec" -eq 0 && "$out" != *NEED_PASSWORD* ]]; then
	ok "stale log secrets ignored"
else
	fail "stale log secrets ignored (ec=$ec out=$out)"
fi

# --- nmcli up returns 0 but radio stays on Home → must not claim 已连接
st="$WORKDIR/s7"
mkdir -p "$st"
echo uuid-home >"$st/active"
echo "HomeNet" >"$st/ssid.uuid-home"
echo wpa-psk >"$st/km.uuid-home"
echo 0 >"$st/flags.uuid-home"
echo "Cafe" >"$st/ssid.uuid-cafe"
echo wpa-psk >"$st/km.uuid-cafe"
echo 0 >"$st/flags.uuid-cafe"
echo secret >"$st/psk.uuid-cafe"
touch "$st/psk_visible"
touch "$st/up_noop"
run_capture "$st" "Cafe" "correct-password" "wlan0" "WPA2"
if [[ "$ec" -ne 0 && "$out" != *已连接* ]]; then
	ok "false nmcli up is not 已连接"
else
	fail "false nmcli up is not 已连接 (ec=$ec out=$out)"
fi

# --- forget deletes the profile and drops the radio if it was in use
st="$WORKDIR/s6"
mkdir -p "$st"
echo "Cafe" >"$st/ssid.uuid-cafe"
echo uuid-cafe >"$st/active"
run_capture "$st" forget "Cafe" "wlan0"
if [[ "$ec" -eq 0 && "$out" == *已忘记* && ! -f "$st/ssid.uuid-cafe" && ! -f "$st/active" ]]; then
	ok "forget deletes profile"
else
	fail "forget deletes profile (ec=$ec out=$out active=$(ls "$st/active" 2>/dev/null || echo none))"
fi

set +e
out=$(FAKE_NM_STATE="$WORKDIR" NMCLI="$FAKE" GEMINI_WIFI_LOG="$WORKDIR/wifi.log" TMPDIR="$WORKDIR" "$SCRIPT")
ec=$?
set -e
if [[ "$ec" -ne 0 ]]; then
	ok "empty ssid fails"
else
	fail "empty ssid fails"
fi

if [[ "$fails" -ne 0 ]]; then
	echo "# $fails script tests failed"
	exit 1
fi
echo "# script tests passed"
exit 0
