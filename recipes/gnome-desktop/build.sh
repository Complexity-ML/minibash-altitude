#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/gnome-desktop}"
VERSION=44.5
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
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" gnome-desktop)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || { echo "gnome-desktop: missing build tool: $tool" >&2; exit 1; }
done
for tool in meson ninja; do
  command -v "$tool" >/dev/null ||
    { echo "gnome-desktop: missing forge tool: $tool" >&2; exit 1; }
done
for dep in gdk-pixbuf-2.0 gtk4 glib-2.0 gio-2.0 gio-unix-2.0 \
  gsettings-desktop-schemas fontconfig xkeyboard-config iso-codes libseccomp; do
  "$PKG_CONFIG" --exists "$dep" ||
    { echo "gnome-desktop: target dependency missing from $SYSROOT: $dep" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1
sed -i "s/libgnome_rr_gir = ''/libgnome_rr_gir = []/" \
  "$WORK/source/libgnome-desktop/gnome-rr/meson.build"

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

[built-in options]
c_args = ['-O2', '-pipe']
c_link_args = ['-Wl,-rpath-link,$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib64']
EOF

meson setup "$WORK/build" "$WORK/source" \
  --cross-file="$WORK/cross.ini" --prefix=/usr --libdir=lib \
  --buildtype=release --wrap-mode=nofallback \
  -Ddesktop_docs=false -Ddebug_tools=false -Dintrospection=false \
  -Dudev=disabled -Dsystemd=disabled -Dgtk_doc=false \
  -Dinstalled_tests=false -Dbuild_gtk4=true -Dlegacy_library=false
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

find "$PAYLOAD/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done
install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: gnome-desktop"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: GTK 4, no GTK 3 legacy library, no systemd/udev, cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/gnome-desktop.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/gnome-desktop/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-gnome-desktop-$VERSION-amd64.altpkg"
