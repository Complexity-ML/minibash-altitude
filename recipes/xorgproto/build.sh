#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/xorgproto}"
VERSION=2024.1
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" xorgproto)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export CC="$TOOLCHAIN/bin/$TARGET-gcc"
export AR="$TOOLCHAIN/bin/$TARGET-ar"

for tool in meson ninja; do
  command -v "$tool" >/dev/null ||
    { echo "xorgproto: missing host build tool: $tool" >&2; exit 1; }
done
[ -x "$CC" ] || { echo "xorgproto: missing Altitude compiler: $CC" >&2; exit 1; }
[ -x "$AR" ] || { echo "xorgproto: missing Altitude archiver: $AR" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

meson setup "$WORK/build" "$WORK/source" \
  --prefix=/usr --datadir=share --buildtype=release
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: xorgproto"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: architecture-independent X.Org protocol headers"
} > "$PAYLOAD/usr/share/altitude/sources/xorgproto.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/xorgproto/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-xorgproto-$VERSION-amd64.altpkg"
