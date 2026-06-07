#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/libepoxy}"
VERSION=1.5.10
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
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" libepoxy)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || { echo "libepoxy: missing build tool: $tool" >&2; exit 1; }
done
for tool in meson ninja python3; do
  command -v "$tool" >/dev/null ||
    { echo "libepoxy: missing host build tool: $tool" >&2; exit 1; }
done
"$PKG_CONFIG" --exists egl ||
  { echo "libepoxy: target EGL is missing from $SYSROOT" >&2; exit 1; }

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

[built-in options]
c_args = ['-O2', '-pipe']
EOF

meson setup "$WORK/build" "$WORK/source" \
  --cross-file "$WORK/cross.ini" --prefix=/usr --libdir=lib \
  --buildtype=release --default-library=both --wrap-mode=nofallback \
  -Ddocs=false -Dtests=false -Dx11=false -Dglx=no -Degl=yes
meson compile -C "$WORK/build"
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/libepoxy.so.* 2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: libepoxy"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Meson EGL-only shared and static cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/libepoxy.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/libepoxy/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-libepoxy-$VERSION-amd64.altpkg"
