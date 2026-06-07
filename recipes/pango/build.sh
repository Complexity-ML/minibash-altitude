#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/pango}"
VERSION=1.56.4
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
CXX="$TOOLCHAIN/bin/$TARGET-g++"
AR="$TOOLCHAIN/bin/$TARGET-ar"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
PKG_CONFIG="$FORGE/bin/pkg-config"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" pango)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$CXX" "$AR" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || {
    echo "pango: missing build tool: $tool" >&2
    exit 1
  }
done
for tool in meson ninja; do
  command -v "$tool" >/dev/null ||
    { echo "pango: missing host build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

cat > "$WORK/cross.ini" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
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
cpp_args = ['-O2', '-pipe']
c_link_args = ['-Wl,-rpath-link,$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib64', '-Wl,-rpath-link,$WORK/build/pango']
cpp_link_args = ['-Wl,-rpath-link,$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib64', '-Wl,-rpath-link,$WORK/build/pango']
EOF

meson setup "$WORK/build" "$WORK/source" \
  --cross-file "$WORK/cross.ini" --prefix=/usr --libdir=lib \
  --buildtype=release --default-library=both --wrap-mode=nofallback \
  -Dintrospection=disabled -Ddocumentation=false \
  -Dbuild-testsuite=false -Dbuild-examples=false \
  -Dfontconfig=enabled -Dfreetype=enabled -Dcairo=enabled -Dxft=disabled
meson compile -C "$WORK/build"
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/libpango*.so.* 2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: pango"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Meson shared and static cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/pango.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/pango/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-pango-$VERSION-amd64.altpkg"
