#!/usr/bin/env bash
# Create a GitHub Release: boot.img and optional compressed rootfs.
# gemini boots LK. Do not upload a ginkgo-style empty dtbo.
#
# Usage:
#   gh auth login
#   ./scripts/build-bootimg.sh
#   ./scripts/publish-release.sh v0.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-}"
REPO="${GITHUB_REPOSITORY:-Huabin1010/gemini-mainline-linux}"
OUT="$ROOT/out"
BOOT="${BOOTIMG:-$OUT/boot.img}"

usage() {
	echo "usage: $0 vX.Y.Z" >&2
	exit 1
}

[[ -n "$TAG" ]] || usage
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+ ]] || {
	echo "error: tag should look like v0.1.0" >&2
	exit 1
}

command -v gh >/dev/null || {
	echo "error: gh not found (https://cli.github.com/)" >&2
	exit 1
}

if ! gh auth status >/dev/null 2>&1; then
	echo "error: GitHub API not logged in. Run:  gh auth login" >&2
	echo "       git SSH is not enough for Releases." >&2
	exit 1
fi

[[ -f "$BOOT" ]] || { echo "error: missing $BOOT — run scripts/build-bootimg.sh" >&2; exit 1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cp -a "$BOOT" "$WORKDIR/boot.img"
ASSETS=( "$WORKDIR/boot.img" )

# Never upload out/rootfs.ext4: that image is the maintainer's live root and
# may contain a real password. Only a copy from sanitize-rootfs-for-release.sh.
ROOTFS="${ROOTFS_IMG:-$OUT/rootfs-release.ext4}"
if [[ -f "$ROOTFS" ]]; then
	command -v zstd >/dev/null || { echo "error: zstd required to pack rootfs (apt install zstd)" >&2; exit 1; }
	echo "==> Compressing sanitized $ROOTFS (GitHub rejects a raw 2 GiB file)"
	zstd -T0 -3 -f -o "$WORKDIR/rootfs.ext4.zst" "$ROOTFS"
	ASSETS+=( "$WORKDIR/rootfs.ext4.zst" )
else
	echo "note: no $ROOTFS — Release will be boot.img only"
	echo "      sudo ./scripts/sanitize-rootfs-for-release.sh  then re-run to attach rootfs"
fi

(
	cd "$WORKDIR"
	sha256sum -- "${ASSETS[@]##*/}" > SHA256SUMS
)
ASSETS+=( "$WORKDIR/SHA256SUMS" )

NOTES="$WORKDIR/notes.md"
cat > "$NOTES" <<EOF
Images for **Xiaomi Mi 5 (gemini)**.

This phone uses **LK**, not ABL. Flash \`boot.img\` only for kernel updates. There is **no** empty dtbo. Do not flash ginkgo dtbo/vbmeta.

Flash guide: https://github.com/${REPO}/blob/main/docs/flash-guide.md
Chinese: https://github.com/${REPO}/blob/main/docs/zh-CN/flash-guide.md

If \`rootfs.ext4.zst\` is attached, unpack it with \`zstd -d\` before flashing userdata (this wipes the partition). Set a password with \`passwd\` after first boot. The root password is not in this repository. There is no dtbo image: Mi 5 packs the DTB inside \`boot.img\`.

\`\`\`
fastboot getvar product    # must be gemini
zstd -d rootfs.ext4.zst    # first install only
fastboot flash userdata rootfs.ext4   # first install only
fastboot flash boot boot.img
fastboot reboot
\`\`\`
EOF

echo "==> Creating $REPO release $TAG"
gh release create "$TAG" \
	--repo "$REPO" \
	--title "gemini mainline $TAG" \
	--notes-file "$NOTES" \
	"${ASSETS[@]}"

echo "==> $TAG published"
echo "    https://github.com/${REPO}/releases/tag/${TAG}"
