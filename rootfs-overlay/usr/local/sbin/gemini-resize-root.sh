#!/bin/sh
# Grow the flashed ext4 to the full UFS userdata partition (≈50G).
set -eu
dev=$(findmnt -n -o SOURCE /) || exit 0
[ -b "$dev" ] || exit 0
resize2fs "$dev" || true
