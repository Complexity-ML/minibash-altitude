#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/dosfstools}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
VERSION=4.2
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
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" dosfstools)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP" make; do
  command -v "$tool" >/dev/null || { echo "dosfstools: missing build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

BUILD_TRIPLET="$("$WORK/source/config.guess")"
(
  cd "$WORK/build"
  CC="$CC" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" \
    "$WORK/source/configure" \
      --build="$BUILD_TRIPLET" \
      --host="$TARGET" \
      --prefix=/usr \
      --sbindir=/usr/sbin
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

ln -sf fatlabel "$PAYLOAD/usr/sbin/dosfslabel"
ln -sf mkfs.fat "$PAYLOAD/usr/sbin/mkdosfs"
ln -sf fsck.fat "$PAYLOAD/usr/sbin/fsck.vfat"

find "$PAYLOAD/usr/sbin" -type f -perm -0100 -exec "$STRIP" --strip-unneeded {} + \
  2>/dev/null || true

install -d "$SYSROOT/usr/sbin"
cp -a "$PAYLOAD/usr/sbin/." "$SYSROOT/usr/sbin/"

{
  echo "Source: dosfstools"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: FAT/VFAT utilities cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/dosfstools.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/dosfstools/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-dosfstools-$VERSION-amd64.altpkg"
