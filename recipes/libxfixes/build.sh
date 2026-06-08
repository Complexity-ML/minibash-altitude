#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/libxfixes}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
VERSION=6.0.1
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" libXfixes)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for dep in x11 fixesproto; do
  "$FORGE/bin/pkg-config" --exists "$dep" ||
    { echo "libxfixes: target dependency missing from $SYSROOT: $dep" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source"
  ./configure --host="$TARGET" --prefix=/usr --libdir=/usr/lib \
    --enable-shared --enable-static \
    CC="$TOOLCHAIN/bin/$TARGET-gcc" AR="$TOOLCHAIN/bin/$TARGET-ar" \
    RANLIB="$TOOLCHAIN/bin/$TARGET-ranlib" CFLAGS="-O2 -pipe"
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

find "$PAYLOAD/usr/lib" -name '*.la' -delete
"$TOOLCHAIN/bin/$TARGET-strip" --strip-unneeded \
  "$PAYLOAD"/usr/lib/libXfixes.so.* 2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: libXfixes"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: shared and static cross $TARGET"
  echo "Compiler: $("$TOOLCHAIN/bin/$TARGET-gcc" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/libxfixes.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/libxfixes/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-libxfixes-$VERSION-amd64.altpkg"
