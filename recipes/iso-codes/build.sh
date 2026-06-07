#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/iso-codes}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
VERSION=4.18.0
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" iso-codes)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source"
  ./configure --prefix=/usr --libdir=/usr/lib
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: iso-codes"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Autotools data install for $TARGET"
} > "$PAYLOAD/usr/share/altitude/sources/iso-codes.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/iso-codes/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-iso-codes-$VERSION-amd64.altpkg"
