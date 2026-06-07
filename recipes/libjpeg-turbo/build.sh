#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/libjpeg-turbo}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
VERSION=3.1.2
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" libjpeg-turbo)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in cmake ninja "$TARGET-gcc" "$TARGET-g++" "$TARGET-ar" "$TARGET-ranlib" "$TARGET-strip"; do
  command -v "$tool" >/dev/null || {
    echo "libjpeg-turbo: missing Altitude tool: $tool" >&2
    exit 1
  }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

cat > "$WORK/toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_SYSROOT "$SYSROOT")
set(CMAKE_C_COMPILER "$TOOLCHAIN/bin/$TARGET-gcc")
set(CMAKE_CXX_COMPILER "$TOOLCHAIN/bin/$TARGET-g++")
set(CMAKE_AR "$TOOLCHAIN/bin/$TARGET-ar")
set(CMAKE_RANLIB "$TOOLCHAIN/bin/$TARGET-ranlib")
set(CMAKE_STRIP "$TOOLCHAIN/bin/$TARGET-strip")
set(CMAKE_FIND_ROOT_PATH "$SYSROOT")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF

cmake -S "$WORK/source" -B "$WORK/build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$WORK/toolchain.cmake" \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SHARED=ON \
  -DENABLE_STATIC=ON \
  -DWITH_SIMD=OFF \
  -DWITH_JPEG8=ON \
  -DWITH_TURBOJPEG=ON \
  -DWITH_TESTS=OFF
cmake --build "$WORK/build" -j"$JOBS"
DESTDIR="$PAYLOAD" cmake --install "$WORK/build"

find "$PAYLOAD/usr/lib" -name '*.la' -delete 2>/dev/null || true
"$TOOLCHAIN/bin/$TARGET-strip" --strip-unneeded \
  "$PAYLOAD"/usr/lib/libjpeg.so.* "$PAYLOAD"/usr/lib/libturbojpeg.so.* \
  2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: libjpeg-turbo"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: CMake shared and static cross $TARGET, SIMD disabled"
  echo "Compiler: $("$TOOLCHAIN/bin/$TARGET-gcc" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/libjpeg-turbo.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/libjpeg-turbo/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-libjpeg-turbo-$VERSION-amd64.altpkg"
