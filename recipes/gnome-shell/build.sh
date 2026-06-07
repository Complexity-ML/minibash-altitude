#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/gnome-shell}"
VERSION=48.8
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
EXE_WRAPPER="${ALTITUDE_EXE_WRAPPER:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
PKG_CONFIG="$FORGE/bin/pkg-config"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" gnome-shell)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || { echo "gnome-shell: missing build tool: $tool" >&2; exit 1; }
done
for tool in meson ninja python3 gjs g-ir-scanner g-ir-compiler sassc; do
  command -v "$tool" >/dev/null ||
    { echo "gnome-shell: missing forge tool: $tool" >&2; exit 1; }
done
[ -n "$EXE_WRAPPER" ] && [ -x "$EXE_WRAPPER" ] || {
  echo "gnome-shell: ALTITUDE_EXE_WRAPPER must name an executable target runner" >&2
  exit 1
}
for dep in atk-bridge-2.0 libecal-2.0 libedataserver-1.2 gcr-4 \
  gdk-pixbuf-2.0 gobject-introspection-1.0 gio-2.0 gio-unix-2.0 gjs-1.0 \
  gtk4 libxml-2.0 mutter-clutter-16 mutter-mtk-16 mutter-cogl-16 \
  libmutter-16 polkit-agent-1 gsettings-desktop-schemas gnome-desktop-4 \
  pango libpulse libpulse-mainloop-glib alsa; do
  "$PKG_CONFIG" --exists "$dep" ||
    { echo "gnome-shell: target dependency missing from $SYSROOT: $dep" >&2; exit 1; }
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
exe_wrapper = '$EXE_WRAPPER'

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
  -Dcamera_monitor=false -Dextensions_tool=false -Dextensions_app=false \
  -Dgtk_doc=false -Dman=false -Dtests=false \
  -Dnetworkmanager=false -Dportal_helper=false -Dsystemd=false
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

find "$PAYLOAD/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done
install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: gnome-shell"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Wayland shell without systemd, NetworkManager or portal helper, cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/gnome-shell.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/gnome-shell/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-gnome-shell-$VERSION-amd64.altpkg"
