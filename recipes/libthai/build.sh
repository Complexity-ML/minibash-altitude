#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/libthai}"
VERSION=0.1.30
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
PKG_CONFIG="$FORGE/bin/pkg-config"
TRIETOOL="$FORGE/bin/trietool-0.2"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" libthai)"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"

[ -x "$TRIETOOL" ] || TRIETOOL="$FORGE/bin/trietool"
export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP" "$PKG_CONFIG" "$TRIETOOL"; do
  [ -x "$tool" ] || { echo "libthai: missing build tool: $tool" >&2; exit 1; }
done
"$PKG_CONFIG" --exists datrie-0.2 ||
  { echo "libthai: target datrie-0.2 is missing from $SYSROOT" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

BUILD_TRIPLET="$("$WORK/source/build-aux/config.guess")"
(
  cd "$WORK/source"
  CC="$CC" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" \
    PKG_CONFIG="$PKG_CONFIG" TRIETOOL="$TRIETOOL" \
    ./configure \
      --build="$BUILD_TRIPLET" --host="$TARGET" \
      --prefix=/usr --libdir=/usr/lib \
      --enable-shared --enable-static --disable-doxygen-doc
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/libthai.so.* 2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: libthai"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Autotools shared and static cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/libthai.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/libthai/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-libthai-$VERSION-amd64.altpkg"
