#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/ninja}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
PREFIX="/opt/altitude/forge"
VERSION=1.13.2
PYTHON="$FORGE_ROOT$PREFIX/bin/python3"
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
COMPILER="${CXX:-$TOOLCHAIN/bin/$TARGET-g++}"
STRIP="${STRIP:-$TOOLCHAIN/bin/$TARGET-strip}"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" ninja)"

[ -x "$PYTHON" ] || {
  echo "ninja: Altitude Python build runtime missing: $PYTHON" >&2
  exit 1
}
command -v "$COMPILER" >/dev/null 2>&1 || {
  echo "ninja: C++ compiler missing: $COMPILER" >&2
  exit 1
}
[ -x "$STRIP" ] || {
  echo "ninja: strip missing: $STRIP" >&2
  exit 1
}

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/payload$PREFIX/bin" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source"
  CXX="$COMPILER" "$PYTHON" configure.py --bootstrap
)

install -m755 "$WORK/source/ninja" "$WORK/payload$PREFIX/bin/ninja"
"$STRIP" --strip-unneeded "$WORK/payload$PREFIX/bin/ninja" 2>/dev/null || true

{
  echo "Source: ninja"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: configure.py bootstrap with Altitude forge Python"
  echo "Compiler: $("$COMPILER" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/ninja.build"

"$WORK/payload$PREFIX/bin/ninja" --version | grep -qx "$VERSION"

if [ -d "$PREFIX/bin" ]; then
  cp -a "$WORK/payload$PREFIX/." "$PREFIX/"
fi

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/ninja/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-ninja-$VERSION-amd64.altpkg"
