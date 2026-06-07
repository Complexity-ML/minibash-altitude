#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/gnome-session}"
VERSION=48.0
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
PKG_CONFIG="$FORGE/bin/pkg-config"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" gnome-session)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || { echo "gnome-session: missing build tool: $tool" >&2; exit 1; }
done
for tool in meson ninja glib-compile-schemas; do
  command -v "$tool" >/dev/null ||
    { echo "gnome-session: missing forge tool: $tool" >&2; exit 1; }
done
for dep in gio-2.0 glib-2.0 gtk+-3.0 gnome-desktop-3.0 json-glib-1.0 \
  gio-unix-2.0 systemd libsystemd; do
  "$PKG_CONFIG" --exists "$dep" ||
    { echo "gnome-session: target dependency missing from $SYSROOT: $dep" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

cat > "$WORK/cross.ini" <<EOF
[binaries]
c = '$CC'
ar = '$AR'
strip = '$STRIP'
pkg-config = '$PKG_CONFIG'

[properties]
sys_root = '$SYSROOT'
pkg_config_libdir = '$PKG_CONFIG_LIBDIR'
needs_exe_wrapper = true

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

meson setup "$WORK/build" "$WORK/source" \
  --cross-file="$WORK/cross.ini" --prefix=/usr --libdir=lib \
  --sysconfdir=/etc --buildtype=release --wrap-mode=nofallback \
  -Dsession_selector=false -Ddocbook=false -Dman=false -Dx11=false
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

find "$PAYLOAD/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done

{
  echo "Source: gnome-session"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Wayland session, no X11 or documentation, cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/gnome-session.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/gnome-session/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-gnome-session-$VERSION-amd64.altpkg"
