#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/libxdmcp}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
VERSION=1.1.5
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" libXdmcp)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source"
  ./configure --host="$TARGET" --prefix=/usr --libdir=/usr/lib \
    --enable-shared --enable-static \
    CC="$TOOLCHAIN/bin/$TARGET-gcc" AR="$TOOLCHAIN/bin/$TARGET-ar" \
    RANLIB="$TOOLCHAIN/bin/$TARGET-ranlib" CFLAGS="-O2 -pipe"
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

find "$PAYLOAD/usr/lib" -name '*.la' -delete
"$TOOLCHAIN/bin/$TARGET-strip" --strip-unneeded \
  "$PAYLOAD"/usr/lib/libXdmcp.so.* 2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: libXdmcp"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: shared and static cross $TARGET"
  echo "Compiler: $("$TOOLCHAIN/bin/$TARGET-gcc" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/libxdmcp.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/libxdmcp/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-libxdmcp-$VERSION-amd64.altpkg"
