#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/libcap}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
VERSION=2.76
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
RANLIB="$TOOLCHAIN/bin/$TARGET-ranlib"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" libcap)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP" make; do
  command -v "$tool" >/dev/null || { echo "libcap: missing build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source/libcap"
  make -j"$JOBS" CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    prefix=/usr lib=lib RAISE_SETFCAP=no PAM_CAP=no
  make DESTDIR="$PAYLOAD" prefix=/usr lib=lib RAISE_SETFCAP=no PAM_CAP=no install
)

"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/libcap.so.* 2>/dev/null || true
install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: libcap"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: libcap library cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/libcap.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/libcap/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-libcap-$VERSION-amd64.altpkg"
