#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/wayland-protocols}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
VERSION=1.48
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" wayland_protocols)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$FORGE/lib/pkgconfig:$FORGE/lib64/pkgconfig:$FORGE/share/pkgconfig:$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
for tool in meson ninja; do
  command -v "$tool" >/dev/null || {
    echo "wayland-protocols: missing Altitude forge tool: $tool" >&2
    exit 1
  }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

meson setup "$WORK/build" "$WORK/source" \
  --prefix=/usr --datadir=share --buildtype=release -Dtests=false
DESTDIR="$WORK/payload" ninja -C "$WORK/build" install

install -d "$SYSROOT/usr/share"
cp -a "$WORK/payload/usr/share/wayland-protocols" "$SYSROOT/usr/share/"
install -d "$SYSROOT/usr/share/pkgconfig"
cp -a "$WORK/payload/usr/share/pkgconfig/wayland-protocols.pc" \
  "$SYSROOT/usr/share/pkgconfig/"

{
  echo "Source: wayland_protocols"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: architecture-independent protocol data"
} > "$WORK/payload/usr/share/altitude/sources/wayland-protocols.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/wayland-protocols/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-wayland-protocols-$VERSION-amd64.altpkg"
