#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/libseccomp}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
VERSION=2.6.0
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
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" libseccomp)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP"; do
  [ -x "$tool" ] || { echo "libseccomp: missing build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

BUILD_TRIPLET="$("$WORK/source/build-aux/config.guess")"
(
  cd "$WORK/source"
  CC="$CC" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" \
    LDFLAGS="-Wl,-rpath-link,$SYSROOT/usr/lib -Wl,-rpath-link,$SYSROOT/usr/lib64" \
    ./configure --build="$BUILD_TRIPLET" --host="$TARGET" \
      --prefix=/usr --libdir=/usr/lib \
      --enable-shared --enable-static --disable-python
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

find "$PAYLOAD/usr/lib" -name '*.la' -delete
"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/libseccomp.so.* 2>/dev/null || true
install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: libseccomp"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Autotools shared and static cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/libseccomp.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/libseccomp/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-libseccomp-$VERSION-amd64.altpkg"
