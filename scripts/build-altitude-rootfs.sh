#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${ALTITUDE_REPO_ROOT:-$ROOT/out/repository}"
DEST="${ALTITUDE_ROOTFS_DIR:-$ROOT/out/altitude-rootfs}"
ROOTFS_TGZ="${ROOTFS_TGZ:-$ROOT/out/altitude-rootfs.tar.gz}"
PROFILE="${ALTITUDE_PROFILE:-desktop}"

case "$PROFILE" in
  desktop|rescue) ;;
  *) echo "unknown ALTITUDE_PROFILE=$PROFILE (desktop, rescue)" >&2; exit 1 ;;
esac

require_package() {
  local package="$1"
  grep -q "^Package: $package$" "$REPO/INDEX" 2>/dev/null || {
    echo "missing native Altitude package: $package" >&2
    exit 1
  }
}

base_packages=(
  altitude-base
  altitude-kernel
  altitude-firmware
  altitude-identity
  altitude-core
  altitude-services
  altitude-access
)

desktop_packages=(
  altitude-python-build-runtime
  altitude-meson
  altitude-ninja
  altitude-cmake
  altitude-dbus
  altitude-glib
  altitude-wayland
  altitude-wayland-protocols
  altitude-libdrm
  altitude-mesa
  altitude-gtk4
  altitude-gsettings-desktop-schemas
  altitude-gnome-desktop
  altitude-mutter
  altitude-gnome-shell
  altitude-gnome-session
  altitude-elogind
  altitude-polkit
  altitude-accountsservice
  altitude-upower
  altitude-udisks
)

packages=("${base_packages[@]}")
if [ "$PROFILE" = "desktop" ]; then
  packages+=("${desktop_packages[@]}")
fi

[ -f "$REPO/INDEX" ] || {
  echo "missing repository index: $REPO/INDEX" >&2
  echo "Build the native .altpkg repository first." >&2
  exit 1
}

for package in "${packages[@]}"; do
  require_package "$package"
done

bash "$ROOT/scripts/assemble-altitude-rootfs.sh" "$REPO" "$DEST" "${packages[@]}"
mkdir -p "$DEST"/{dev,proc,run,sys,tmp}
chmod 1777 "$DEST/tmp"

tar --numeric-owner --owner=0 --group=0 -czf "$ROOTFS_TGZ" -C "$DEST" .
echo "Altitude $PROFILE rootfs: $ROOTFS_TGZ"
