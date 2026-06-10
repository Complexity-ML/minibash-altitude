#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/lz4}"
VERSION=1.10.0
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" lz4)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"

[ -x "$CC" ] || { echo "lz4: missing compiler: $CC" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

make -C "$WORK/source/lib" CC="$CC" AR="$AR" PREFIX=/usr LIBDIR=/usr/lib
make -C "$WORK/source/lib" DESTDIR="$PAYLOAD" PREFIX=/usr LIBDIR=/usr/lib install
"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/liblz4.so.* 2>/dev/null || true

install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: lz4"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: shared library cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/lz4.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/lz4/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-lz4-$VERSION-amd64.altpkg"
