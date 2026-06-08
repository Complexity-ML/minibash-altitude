#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/geocode-glib}"
VERSION=3.26.4
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
READELF="$TOOLCHAIN/bin/$TARGET-readelf"
PKG_CONFIG="$FORGE/bin/pkg-config"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" geocode-glib)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$STRIP" "$READELF" "$PKG_CONFIG"; do
  [ -x "$tool" ] || { echo "geocode-glib: missing build tool: $tool" >&2; exit 1; }
done
for tool in meson ninja; do
  command -v "$tool" >/dev/null ||
    { echo "geocode-glib: missing host build tool: $tool" >&2; exit 1; }
done
for dep in gio-2.0 json-glib-1.0 libsoup-3.0 gobject-introspection-1.0; do
  "$PKG_CONFIG" --exists "$dep" ||
    { echo "geocode-glib: target dependency missing: $dep" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$WORK/tools" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

cat > "$WORK/tools/ldd" <<EOF
#!/bin/sh
"$READELF" -d "\$1" 2>/dev/null | awk '
  /NEEDED/ {
    lib = \$0
    sub(/^.*\\[/, "", lib)
    sub(/\\].*$/, "", lib)
    print "\\t" lib " => " lib " (0x00000000)"
  }
'
EOF
chmod +x "$WORK/tools/ldd"
export PATH="$WORK/tools:$PATH"

sed -i "s/export_packages: 'geocode-glib-1.0'/export_packages: 'geocode-glib-@0@'.format(gclib_api_version)/" \
  "$WORK/source/geocode-glib/meson.build"
sed -i "s/^subdir('tests')/# tests disabled for Altitude package/" \
  "$WORK/source/geocode-glib/meson.build"

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
c_link_args = ['-Wl,-rpath-link,$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib64', '-Wl,-rpath-link,$SYSROOT/lib', '-Wl,-rpath-link,$SYSROOT/lib64']
EOF

meson setup "$WORK/build" "$WORK/source" \
  --cross-file="$WORK/cross.ini" \
  --prefix=/usr --libdir=lib --libexecdir=libexec \
  --buildtype=release --default-library=both --wrap-mode=nofallback \
  -Dsoup2=false -Denable-introspection=true \
  -Denable-installed-tests=false -Denable-gtk-doc=false
meson compile -C "$WORK/build"
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

find "$PAYLOAD/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: geocode-glib"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: libsoup3 geocode-glib-2.0 library cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/geocode-glib.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/geocode-glib/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-geocode-glib-$VERSION-amd64.altpkg"
