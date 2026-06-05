#!/usr/bin/env bash
# Assemble the disk image from the debootstrap Debian rootfs, using the rootfs's
# OWN kernel + modules (so the running kernel matches /lib/modules on disk).
# Run after build-disk-rootfs.sh.
set -euo pipefail

DISTRO_DIR="${DISTRO_DIR:-/work/minibash-linux}"
OUT_DIR="${OUT_DIR:-$DISTRO_DIR/out}"
ROOTFS_TGZ="${ROOTFS_TGZ:-$OUT_DIR/minibash-rootfs.tar.gz}"

log() { printf '[minibash:debimg] %s\n' "$*"; }

ROOTDIR=/tmp/mb-deb-extract
rm -rf "$ROOTDIR"; mkdir -p "$ROOTDIR"
log "extracting Debian rootfs to detect kernel/modules"
tar -xzf "$ROOTFS_TGZ" -C "$ROOTDIR"

ver="$(ls "$ROOTDIR/lib/modules" | head -1)"
kernel="$ROOTDIR/boot/vmlinuz-$ver"
[ -f "$kernel" ] || { echo "no kernel /boot/vmlinuz-$ver in rootfs" >&2; exit 1; }
log "rootfs kernel: $ver"

# Boot initramfs built from the ROOTFS's modules (matching the kernel).
SKIP_ROOTFS=1 KERNEL_MODULES_DIR="$ROOTDIR" \
  bash "$DISTRO_DIR/build-disk.sh"

# Disk image using the rootfs's own kernel.
KERNEL_IMAGE="$kernel" \
  bash "$DISTRO_DIR/build-disk-image.sh"

log "Debian disk image ready (kernel $ver)"
