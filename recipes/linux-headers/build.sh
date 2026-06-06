#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/linux-headers}"
PREFIX="/opt/altitude/toolchain"
SYSROOT="$PREFIX/sysroot"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" linux)"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/payload$SYSROOT/usr" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

make -C "$WORK/source" -j"$JOBS" ARCH=x86 \
  headers_install \
  INSTALL_HDR_PATH="$WORK/payload$SYSROOT/usr"

find "$WORK/payload$SYSROOT/usr/include" \
  \( -name '.install' -o -name '*.cmd' \) -delete

{
  echo "Source: linux"
  echo "Version: 7.0.10"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Architecture: x86"
  echo "Stage: bootstrap-1"
} > "$WORK/payload/usr/share/altitude/sources/linux-headers.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/linux-headers/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-linux-headers-7.0.10-amd64.altpkg"
