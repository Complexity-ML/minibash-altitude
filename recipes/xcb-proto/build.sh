#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/xcb-proto}"
VERSION=1.17.0
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" xcb-proto)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"

for tool in python3; do
  command -v "$tool" >/dev/null ||
    { echo "xcb-proto: missing host build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source"
  ./configure --prefix=/usr --datadir=/usr/share PYTHON=python3
  make
  make DESTDIR="$PAYLOAD" install
)

install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: xcb-proto"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: architecture-independent XCB protocol data"
} > "$PAYLOAD/usr/share/altitude/sources/xcb-proto.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/xcb-proto/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-xcb-proto-$VERSION-amd64.altpkg"
