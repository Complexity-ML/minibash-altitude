#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/pcre2}"
VERSION=10.47
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
SYSROOT="$TOOLCHAIN/sysroot"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
RANLIB="$TOOLCHAIN/bin/$TARGET-ranlib"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" pcre2)"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP"; do
  [ -x "$tool" ] || { echo "pcre2: missing toolchain component: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/build"
  CC="$CC" AR="$AR" RANLIB="$RANLIB" \
  CFLAGS="-O2 -pipe" \
    "$WORK/source/configure" \
      --build="$( "$WORK/source/config.guess" )" \
      --host="$TARGET" \
      --prefix=/usr \
      --libdir=/usr/lib \
      --enable-shared \
      --enable-static \
      --enable-pcre2-8 \
      --disable-pcre2-16 \
      --disable-pcre2-32 \
      --enable-unicode \
      --disable-jit \
      --disable-pcre2grep-libz \
      --disable-pcre2grep-libbz2 \
      --disable-pcre2test-libreadline
  make -j"$JOBS"
  make DESTDIR="$WORK/payload" install
)

find "$WORK/payload/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done

install -d "$SYSROOT/usr/include" "$SYSROOT/usr/lib"
cp -a "$WORK/payload/usr/include/." "$SYSROOT/usr/include/"
cp -a "$WORK/payload/usr/lib/." "$SYSROOT/usr/lib/"

{
  echo "Source: pcre2"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: 8-bit Unicode shared+static cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/pcre2.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/pcre2/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-pcre2-$VERSION-amd64.altpkg"
