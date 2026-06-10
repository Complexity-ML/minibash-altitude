#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
IMAGE="${1:-$OUT_DIR/altitude-linux-disk.img}"
ROOTFS="${ROOTFS_TGZ:-$OUT_DIR/altitude-rootfs.tar.gz}"
RELEASE_DIR="${RELEASE_DIR:-$OUT_DIR/release}"
VERSION="${ALTITUDE_VERSION:-$(cat "$ROOT/rootfs/etc/minibash/VERSION" 2>/dev/null || echo 0.1.0)}"
CODENAME="${ALTITUDE_CODENAME:-basecamp}"
STAMP="${ALTITUDE_RELEASE_STAMP:-$(date -u +%Y%m%d)}"
BASE="altitude-linux-${VERSION}-${CODENAME}-${STAMP}-x86_64"

die() { echo "release-image: $*" >&2; exit 1; }
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
size_bytes() {
  if stat -c %s "$1" >/dev/null 2>&1; then
    stat -c %s "$1"
  else
    stat -f %z "$1"
  fi
}

[ -f "$IMAGE" ] || die "missing image: $IMAGE"
[ -f "$ROOTFS" ] || die "missing rootfs: $ROOTFS"
mkdir -p "$RELEASE_DIR"

image_name="$BASE.img"
manifest="$RELEASE_DIR/$BASE.MANIFEST"
checksums="$RELEASE_DIR/SHA256SUMS"
readme="$RELEASE_DIR/README-$BASE.txt"

ln -sf "../$(basename "$IMAGE")" "$RELEASE_DIR/$image_name"

image_sha="$(hash_file "$IMAGE")"
rootfs_sha="$(hash_file "$ROOTFS")"
commit="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
dirty="$(git -C "$ROOT" status --short 2>/dev/null | wc -l | tr -d ' ')"

{
  echo "Name: Altitude Linux"
  echo "Version: $VERSION"
  echo "Codename: $CODENAME"
  echo "Architecture: x86_64"
  echo "Profile: desktop"
  echo "Init: systemd"
  echo "Desktop: GNOME"
  echo "Package-Manager: altpkg"
  echo "Registry-Mode: audit"
  echo "Image: $image_name"
  echo "Image-Bytes: $(size_bytes "$IMAGE")"
  echo "Image-SHA256: $image_sha"
  echo "Rootfs: $(basename "$ROOTFS")"
  echo "Rootfs-Bytes: $(size_bytes "$ROOTFS")"
  echo "Rootfs-SHA256: $rootfs_sha"
  echo "Git-Commit: $commit"
  echo "Git-Dirty-Files: $dirty"
  echo "Built-UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Root-Label: altitude-native"
  echo "EFI-Label: ALTITUDEEFI"
  echo "Bootloader: EFI/BOOT/BOOTX64.EFI"
} > "$manifest"

{
  printf '%s  %s\n' "$image_sha" "$image_name"
  printf '%s  ../%s\n' "$rootfs_sha" "$(basename "$ROOTFS")"
  printf '%s  %s\n' "$(hash_file "$manifest")" "$(basename "$manifest")"
} > "$checksums"

cat > "$readme" <<EOF
Altitude Linux $VERSION ($CODENAME) x86_64 desktop image

Contents:
  $image_name
  $(basename "$manifest")
  SHA256SUMS

This is a native Altitude image:
  - Linux kernel and root filesystem from Altitude packages
  - systemd as PID 1
  - GNOME desktop profile
  - embedded signed altpkg repository
  - BDB registry used for audit/admin state, not as the service manager

Write to a target disk carefully:
  sudo dd if=$image_name of=/dev/sdX bs=4M status=progress conv=fsync

Verify before writing:
  sha256sum -c SHA256SUMS

Root label: altitude-native
EFI label:  ALTITUDEEFI
EOF

echo "release-image: $manifest"
echo "release-image: $checksums"
echo "release-image: $readme"
