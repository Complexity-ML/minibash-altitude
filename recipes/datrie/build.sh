#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/datrie}"
VERSION=0.2.13
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
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" datrie)"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP"; do
  [ -x "$tool" ] || { echo "datrie: missing build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

CONFIG_GUESS="$WORK/source/config.guess"
[ -x "$CONFIG_GUESS" ] || CONFIG_GUESS="$WORK/source/build-aux/config.guess"
BUILD_TRIPLET="$("$CONFIG_GUESS")"
(
  cd "$WORK/source"
  CC="$CC" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" \
    ./configure --build="$BUILD_TRIPLET" --host="$TARGET" \
      --prefix=/usr --libdir=/usr/lib \
      --enable-shared --enable-static --disable-doxygen-doc
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/libdatrie.so.* 2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

# libthai needs a host trietool while cross-building its generated data.
install -d "$FORGE/bin"
if [ -x "$PAYLOAD/usr/bin/trietool-0.2" ]; then
  cp "$PAYLOAD/usr/bin/trietool-0.2" "$FORGE/bin/trietool-0.2"
  ln -sf trietool-0.2 "$FORGE/bin/trietool"
fi

{
  echo "Source: datrie"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Autotools shared/static cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/datrie.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/datrie/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-datrie-$VERSION-amd64.altpkg"
