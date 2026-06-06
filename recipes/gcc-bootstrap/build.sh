#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/gcc-bootstrap}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
PREFIX="/opt/altitude/toolchain"
TARGET_TRIPLET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
HOST_COMPILER="${CC:-cc}"
GCC_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" gcc)"
GMP_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" gmp)"
MPFR_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" mpfr)"
MPC_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" mpc)"

toolchain_path="$TOOLCHAIN_ROOT$PREFIX"
target_ld="$toolchain_path/bin/$TARGET_TRIPLET-ld"
target_as="$toolchain_path/bin/$TARGET_TRIPLET-as"
export PATH="$toolchain_path/bin:$PATH"
[ -x "$target_ld" ] || {
  echo "gcc-bootstrap: Altitude Binutils missing: $target_ld" >&2
  exit 1
}
[ -x "$target_as" ] || {
  echo "gcc-bootstrap: Altitude Binutils missing: $target_as" >&2
  exit 1
}

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$WORK/payload$PREFIX" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$GCC_TARBALL" -C "$WORK/source" --strip-components=1
mkdir "$WORK/source/gmp" "$WORK/source/mpfr" "$WORK/source/mpc"
tar -xf "$GMP_TARBALL" -C "$WORK/source/gmp" --strip-components=1
tar -xf "$MPFR_TARBALL" -C "$WORK/source/mpfr" --strip-components=1
tar -xf "$MPC_TARBALL" -C "$WORK/source/mpc" --strip-components=1

(
  cd "$WORK/build"
  "$WORK/source/configure" \
    --target="$TARGET_TRIPLET" \
    --prefix="$PREFIX" \
    --with-as="$target_as" \
    --with-ld="$target_ld" \
    --with-sysroot="$PREFIX/sysroot" \
    --with-newlib \
    --without-headers \
    --with-pkgversion="Altitude Linux 0.1 bootstrap" \
    --with-bugurl="https://github.com/Complexity-ML/minibash-altitude/issues" \
    --enable-languages=c \
    --disable-bootstrap \
    --disable-decimal-float \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libsanitizer \
    --disable-libssp \
    --disable-libstdcxx \
    --disable-libvtv \
    --disable-multilib \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --without-isl
  make -j"$JOBS" all-gcc all-target-libgcc
  make DESTDIR="$WORK/payload" install-gcc install-target-libgcc
)

rm -rf "$WORK/payload$PREFIX/lib/gcc/$TARGET_TRIPLET/14.2.0/plugin/include"
find "$WORK/payload$PREFIX" -type f -perm -0100 -exec strip --strip-unneeded {} + \
  2>/dev/null || true

{
  echo "Source: gcc"
  echo "Version: 14.2.0"
  echo "SHA256: $(sha256sum "$GCC_TARBALL" | awk '{print $1}')"
  echo "GMP-SHA256: $(sha256sum "$GMP_TARBALL" | awk '{print $1}')"
  echo "MPFR-SHA256: $(sha256sum "$MPFR_TARBALL" | awk '{print $1}')"
  echo "MPC-SHA256: $(sha256sum "$MPC_TARBALL" | awk '{print $1}')"
  echo "Target: $TARGET_TRIPLET"
  echo "Stage: bootstrap-1"
  echo "Compiler: $("$HOST_COMPILER" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/gcc-bootstrap.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/gcc-bootstrap/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-gcc-bootstrap-14.2.0-amd64.altpkg"
