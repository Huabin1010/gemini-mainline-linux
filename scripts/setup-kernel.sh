#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/env.sh
source "$ROOT/scripts/env.sh"

TAG="${KERNEL_TAG:-v7.0}"

if [[ -d "$KERNEL_SRC/.git" ]]; then
	echo "Kernel source already present at $KERNEL_SRC"
	git -C "$KERNEL_SRC" describe --tags --always
	exit 0
fi

echo "==> Cloning Linux $TAG (shallow)..."
git clone --depth 1 --branch "$TAG" \
	https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
	"$KERNEL_SRC"

echo "==> gemini DTS:"
ls -la "$KERNEL_SRC/arch/arm64/boot/dts/qcom/msm8996-xiaomi-gemini"* \
	"$KERNEL_SRC/arch/arm64/boot/dts/qcom/msm8996-xiaomi-common"* 2>/dev/null || true
