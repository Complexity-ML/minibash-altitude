#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work}/ensure-forge-make"
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
CC="${CC:-$TOOLCHAIN/bin/$TARGET-gcc}"
AR="${AR:-$TOOLCHAIN/bin/$TARGET-ar}"
RANLIB="${RANLIB:-$TOOLCHAIN/bin/$TARGET-ranlib}"
STRIP="${STRIP:-$TOOLCHAIN/bin/$TARGET-strip}"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" make)"

if [ -x "$FORGE/bin/make" ]; then
  exit 0
fi

for tool in "$CC" "$AR" "$RANLIB" "$STRIP"; do
  [ -x "$tool" ] || { echo "ensure-forge-make: missing build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$FORGE/bin"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source"
  CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
    --prefix="$FORGE" \
    --disable-nls \
    --disable-dependency-tracking
  CC="$CC" AR="$AR" RANLIB="$RANLIB" ./build.sh
)

cp "$WORK/source/make" "$FORGE/bin/make"
chmod +x "$FORGE/bin/make"
"$STRIP" --strip-unneeded "$FORGE/bin/make" 2>/dev/null || true

printf 'ensure-forge-make: installed %s\n' "$("$FORGE/bin/make" --version | head -1)"
