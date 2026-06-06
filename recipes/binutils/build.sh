#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/binutils}"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" binutils)"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
BUILD_TRIPLET="${ALTITUDE_BUILD_TRIPLET:-}"
TARGET_TRIPLET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
PREFIX="/opt/altitude/toolchain"
COMPILER="${CC:-cc}"

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$WORK/payload$PREFIX" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1
[ -n "$BUILD_TRIPLET" ] ||
  BUILD_TRIPLET="$("$WORK/source/config.guess")"

(
  cd "$WORK/build"
  "$WORK/source/configure" \
    --build="$BUILD_TRIPLET" \
    --host="$BUILD_TRIPLET" \
    --target="$TARGET_TRIPLET" \
    --prefix="$PREFIX" \
    --disable-gdb \
    --disable-gdbserver \
    --disable-gprofng \
    --disable-nls \
    --disable-werror \
    --enable-deterministic-archives
  make -j"$JOBS"
  make DESTDIR="$WORK/payload" install
)

find "$WORK/payload$PREFIX" -type f \
  \( -name '*.la' -o -name '*.a' \) -delete
{
  echo "Source: binutils"
  echo "Version: 2.44"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: $BUILD_TRIPLET"
  echo "Target: $TARGET_TRIPLET"
  echo "Stage: bootstrap-1"
  echo "Compiler: $("$COMPILER" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/binutils.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/binutils/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-binutils-2.44-amd64.altpkg"
