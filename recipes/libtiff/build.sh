#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/libtiff}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
VERSION=4.7.0
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" libtiff)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in gcc g++ ar ranlib strip; do
  [ -x "$TOOLCHAIN/bin/$TARGET-$tool" ] || {
    echo "libtiff: missing Altitude tool: $TOOLCHAIN/bin/$TARGET-$tool" >&2
    exit 1
  }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source"
  ./configure --host="$TARGET" --prefix=/usr --libdir=/usr/lib \
    --enable-shared --enable-static \
    --disable-jpeg --disable-webp --disable-zstd --disable-lzma \
    --disable-jbig --disable-lerc \
    CC="$TOOLCHAIN/bin/$TARGET-gcc" \
    CXX="$TOOLCHAIN/bin/$TARGET-g++" \
    AR="$TOOLCHAIN/bin/$TARGET-ar" \
    RANLIB="$TOOLCHAIN/bin/$TARGET-ranlib" \
    CFLAGS="-O2 -pipe" CXXFLAGS="-O2 -pipe"
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

find "$PAYLOAD/usr/lib" -name '*.la' -delete
"$TOOLCHAIN/bin/$TARGET-strip" --strip-unneeded \
  "$PAYLOAD"/usr/lib/libtiff.so.* "$PAYLOAD"/usr/lib/libtiffxx.so.* \
  2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: libtiff"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: shared and static cross $TARGET"
  echo "Compiler: $("$TOOLCHAIN/bin/$TARGET-gcc" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/libtiff.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/libtiff/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-libtiff-$VERSION-amd64.altpkg"
