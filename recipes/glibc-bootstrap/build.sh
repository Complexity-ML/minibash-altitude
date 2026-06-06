#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/glibc-bootstrap}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
PREFIX="/opt/altitude/toolchain"
FORGE_PREFIX="/opt/altitude/forge"
SYSROOT="$PREFIX/sysroot"
TARGET_TRIPLET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" glibc)"
toolchain_path="$TOOLCHAIN_ROOT$PREFIX"
forge_path="$FORGE_ROOT$FORGE_PREFIX"
export PATH="$forge_path/bin:$toolchain_path/bin:$PATH"
CC="$toolchain_path/bin/$TARGET_TRIPLET-gcc"
AR="$toolchain_path/bin/$TARGET_TRIPLET-ar"
RANLIB="$toolchain_path/bin/$TARGET_TRIPLET-ranlib"
BUILD_TRIPLET="${ALTITUDE_BUILD_TRIPLET:-}"

[ -x "$CC" ] || {
  echo "glibc-bootstrap: Altitude GCC missing: $CC" >&2
  exit 1
}
[ -f "$toolchain_path/sysroot/usr/include/linux/version.h" ] || {
  echo "glibc-bootstrap: Linux headers missing from the sysroot" >&2
  exit 1
}
command -v gawk >/dev/null || {
  echo "glibc-bootstrap: Altitude Gawk missing from $forge_path/bin" >&2
  exit 1
}
command -v bison >/dev/null || {
  echo "glibc-bootstrap: Altitude Bison missing from $forge_path/bin" >&2
  exit 1
}

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$WORK/payload$SYSROOT" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1
for patch_file in "$ROOT/recipes/glibc-bootstrap/patches/"*.patch; do
  patch -d "$WORK/source" -p1 < "$patch_file"
done
[ -n "$BUILD_TRIPLET" ] ||
  BUILD_TRIPLET="$("$WORK/source/scripts/config.guess")"

(
  cd "$WORK/build"
  BUILD_CC="${BUILD_CC:-cc}" \
  CC="$CC" CXX=false AR="$AR" RANLIB="$RANLIB" \
    "$WORK/source/configure" \
      --build="$BUILD_TRIPLET" \
      --host="$TARGET_TRIPLET" \
      --prefix=/usr \
      --with-headers="$toolchain_path/sysroot/usr/include" \
      --enable-kernel=4.19 \
      --disable-werror \
      --disable-nscd \
      libc_cv_slibdir=/usr/lib
  sed -i 's/^CXX = false$/CXX =/' config.make
  make -j"$JOBS"
  make DESTDIR="$WORK/payload$SYSROOT" install
)

find "$WORK/payload$SYSROOT" -type f -perm -0100 -exec strip --strip-unneeded {} + \
  2>/dev/null || true

{
  echo "Source: glibc"
  echo "Version: 2.41"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: $BUILD_TRIPLET"
  echo "Host: $TARGET_TRIPLET"
  echo "Stage: bootstrap-1"
  echo "Patches: 0001-x86_64-bootstrap-libc-sigaction.patch"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/glibc-bootstrap.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/glibc-bootstrap/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-glibc-bootstrap-2.41-amd64.altpkg"
