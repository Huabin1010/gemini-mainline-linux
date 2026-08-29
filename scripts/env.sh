#!/usr/bin/env bash
# Source this file before building: source scripts/env.sh
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export KBUILD_OUTPUT="${KBUILD_OUTPUT:-$ROOT/out/kernel}"
export PATH="$HOME/.local/bin:$PATH"

export KERNEL_SRC="${KERNEL_SRC:-$ROOT/linux}"
export DTB_NAME="${DTB_NAME:-msm8996-xiaomi-gemini.dtb}"
export KERNEL_TAG="${KERNEL_TAG:-v7.0}"
