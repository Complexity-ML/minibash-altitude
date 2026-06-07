#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/cmake}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
PREFIX="/opt/altitude/forge"
VERSION=3.31.7
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
CC_COMPILER="${CC:-$TOOLCHAIN/bin/$TARGET-gcc}"
CXX_COMPILER="${CXX:-$TOOLCHAIN/bin/$TARGET-g++}"
STRIP="${STRIP:-$TOOLCHAIN/bin/$TARGET-strip}"
FORGE="$FORGE_ROOT$PREFIX"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" cmake)"

command -v "$CC_COMPILER" >/dev/null 2>&1 || {
  echo "cmake: C compiler missing: $CC_COMPILER" >&2
  exit 1
}
command -v "$CXX_COMPILER" >/dev/null 2>&1 || {
  echo "cmake: C++ compiler missing: $CXX_COMPILER" >&2
  exit 1
}
[ -x "$STRIP" ] || {
  echo "cmake: strip missing: $STRIP" >&2
  exit 1
}
[ -f "$FORGE/include/openssl/ssl.h" ] || {
  echo "cmake: Altitude forge OpenSSL headers missing from $FORGE" >&2
  exit 1
}

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source"
  export CC="$CC_COMPILER"
  export CXX="$CXX_COMPILER"
  CPPFLAGS="-I$FORGE/include" \
  LDFLAGS="-L$FORGE/lib -Wl,-rpath,$PREFIX/lib" \
  PKG_CONFIG_PATH="$FORGE/lib/pkgconfig" \
    ./bootstrap \
      --prefix="$PREFIX" \
      --parallel="$JOBS" \
      -- \
      -DBUILD_TESTING=OFF \
      -DCMake_ENABLE_DEBUGGER=OFF \
      -DCMAKE_USE_OPENSSL=ON
  make -j"$JOBS"
  make DESTDIR="$WORK/payload" install
)

find "$WORK/payload$PREFIX/bin" -type f -perm -0100 \
  -exec "$STRIP" --strip-unneeded {} + 2>/dev/null || true

{
  echo "Source: cmake"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: native bootstrap with Altitude forge OpenSSL, debugger disabled"
  echo "C-Compiler: $("$CC_COMPILER" --version | head -1)"
  echo "CXX-Compiler: $("$CXX_COMPILER" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/cmake.build"

"$WORK/payload$PREFIX/bin/cmake" --version | grep -q "^cmake version $VERSION$"

if [ -d "$PREFIX/bin" ]; then
  cp -a "$WORK/payload$PREFIX/." "$PREFIX/"
fi

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/cmake/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-cmake-$VERSION-amd64.altpkg"
