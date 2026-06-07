#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/gobject-introspection}"
VERSION=1.84.0
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
PYTHON="$FORGE/bin/python3"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" gobject-introspection)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$STRIP" "$PKG_CONFIG" "$PYTHON"; do
  [ -x "$tool" ] || { echo "gobject-introspection: missing build tool: $tool" >&2; exit 1; }
done
for tool in meson ninja; do
  command -v "$tool" >/dev/null ||
    { echo "gobject-introspection: missing forge tool: $tool" >&2; exit 1; }
done
for dep in glib-2.0 gobject-2.0 gio-2.0 gio-unix-2.0 gmodule-2.0 libffi; do
  "$PKG_CONFIG" --exists "$dep" ||
    { echo "gobject-introspection: target dependency missing from $SYSROOT: $dep" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

sed -i "/python_version.version_compare('>=3.12')/,/endif/d" \
  "$WORK/source/meson.build"

cat > "$WORK/cross.ini" <<EOF
[binaries]
c = '$CC'
ar = '$AR'
strip = '$STRIP'
pkg-config = '$PKG_CONFIG'
python = '$PYTHON'

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
  -Dpython="$PYTHON" -Dgtk_doc=false -Ddoctool=disabled \
  -Dcairo=disabled -Dtests=false -Dbuild_introspection_data=false \
  -Dgi_cross_pkgconfig_sysroot_path="$SYSROOT"
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

find "$PAYLOAD/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done

install -d "$SYSROOT/usr" "$FORGE/bin" "$FORGE/lib"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"
[ -d "$PAYLOAD/usr/bin" ] && cp -a "$PAYLOAD/usr/bin/." "$FORGE/bin/"
[ -d "$PAYLOAD/usr/lib/gobject-introspection" ] && \
  cp -a "$PAYLOAD/usr/lib/gobject-introspection" "$FORGE/lib/"
for pc in "$PAYLOAD/usr/lib/pkgconfig/gobject-introspection-1.0.pc" \
  "$SYSROOT/usr/lib/pkgconfig/gobject-introspection-1.0.pc"; do
  [ -f "$pc" ] || continue
  sed -i \
    -e "s|^g_ir_scanner=.*|g_ir_scanner=$FORGE/bin/g-ir-scanner|" \
    -e "s|^g_ir_compiler=.*|g_ir_compiler=$FORGE/bin/g-ir-compiler|" \
    "$pc"
done

{
  echo "Source: gobject-introspection"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Meson scanner/compiler/libgirepository cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
  echo "Python: $("$PYTHON" --version 2>&1)"
} > "$PAYLOAD/usr/share/altitude/sources/gobject-introspection.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/gobject-introspection/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-gobject-introspection-$VERSION-amd64.altpkg"
