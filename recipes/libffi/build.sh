#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/libffi}"
VERSION=3.5.2
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
SYSROOT="$TOOLCHAIN/sysroot"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
RANLIB="$TOOLCHAIN/bin/$TARGET-ranlib"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" libffi)"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP"; do
  [ -x "$tool" ] || { echo "libffi: missing toolchain component: $tool" >&2; exit 1; }
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
      --disable-docs
  make -j"$JOBS"
  make DESTDIR="$WORK/payload" install
)

find "$WORK/payload/usr/lib" "$WORK/payload/usr/lib64" -type f \
  \( -name '*.so.*' -o -name '*.a' \) -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done

install -d "$SYSROOT/usr/include" "$SYSROOT/usr/lib" "$SYSROOT/usr/lib64"
cp -a "$WORK/payload/usr/include/." "$SYSROOT/usr/include/"
cp -a "$WORK/payload/usr/lib/." "$SYSROOT/usr/lib/"
if [ -d "$WORK/payload/usr/lib64" ]; then
  for name in libffi.so libffi.so.8; do
    if [ ! -e "$WORK/payload/usr/lib/$name" ] && [ -e "$WORK/payload/usr/lib64/$name" ]; then
      ln -sf "../lib64/$name" "$WORK/payload/usr/lib/$name"
    fi
  done
  cp -a "$WORK/payload/usr/lib64/." "$SYSROOT/usr/lib64/"
fi

{
  echo "Source: libffi"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: shared+static cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/libffi.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/libffi/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-libffi-$VERSION-amd64.altpkg"
