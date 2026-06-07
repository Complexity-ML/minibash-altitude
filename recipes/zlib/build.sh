#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/zlib}"
VERSION=1.3.1
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
RANLIB="$TOOLCHAIN/bin/$TARGET-ranlib"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" zlib)"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
PAYLOAD="$WORK/payload"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP"; do
  [ -x "$tool" ] || { echo "zlib: missing toolchain component: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source"
  CHOST="$TARGET" CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CFLAGS="-O2 -pipe" ./configure --prefix=/usr --libdir=/usr/lib
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

find "$PAYLOAD/usr/lib" -name '*.la' -delete
"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/libz.so.* 2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: zlib"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: shared/static cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/zlib.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/zlib/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-zlib-$VERSION-amd64.altpkg"
