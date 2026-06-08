#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/gcc-cxx}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
PREFIX="/opt/altitude/toolchain"
TARGET_TRIPLET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
GCC_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" gcc)"
GMP_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" gmp)"
MPFR_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" mpfr)"
MPC_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" mpc)"

toolchain_path="$TOOLCHAIN_ROOT$PREFIX"
target_gcc="$toolchain_path/bin/$TARGET_TRIPLET-gcc"
target_ld="$toolchain_path/bin/$TARGET_TRIPLET-ld"
target_as="$toolchain_path/bin/$TARGET_TRIPLET-as"
target_tools="$toolchain_path/$TARGET_TRIPLET/bin"
export PATH="$toolchain_path/bin:$target_tools:$PATH"

[ -x "$target_gcc" ] || {
  echo "gcc-cxx: Altitude C compiler missing: $target_gcc" >&2
  exit 1
}
[ -x "$target_ld" ] || {
  echo "gcc-cxx: Altitude linker missing: $target_ld" >&2
  exit 1
}
[ -x "$target_as" ] || {
  echo "gcc-cxx: Altitude assembler missing: $target_as" >&2
  exit 1
}

HOST_CXX="${CXX:-}"
if [ -z "$HOST_CXX" ]; then
  if command -v c++ >/dev/null 2>&1; then
    HOST_CXX="$(command -v c++)"
  elif command -v g++ >/dev/null 2>&1; then
    HOST_CXX="$(command -v g++)"
  fi
fi
[ -n "$HOST_CXX" ] && command -v "$HOST_CXX" >/dev/null 2>&1 || {
  echo "gcc-cxx: no bootstrap C++ compiler found (need c++ or g++ once to build Altitude g++)" >&2
  exit 1
}

HOST_CXX_VERSION="$("$HOST_CXX" --version | head -1)"

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$WORK/payload$PREFIX" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$GCC_TARBALL" -C "$WORK/source" --strip-components=1
mkdir "$WORK/source/gmp" "$WORK/source/mpfr" "$WORK/source/mpc"
tar -xf "$GMP_TARBALL" -C "$WORK/source/gmp" --strip-components=1
tar -xf "$MPFR_TARBALL" -C "$WORK/source/mpfr" --strip-components=1
tar -xf "$MPC_TARBALL" -C "$WORK/source/mpc" --strip-components=1

if [ -n "${ALTITUDE_BOOTSTRAP_CXX_SYSROOT:-}" ]; then
  bootstrap_sysroot="${ALTITUDE_BOOTSTRAP_CXX_SYSROOT%/}"
  bootstrap_cxx="$HOST_CXX"
  HOST_CXX="$WORK/bootstrap-cxx"
  cat > "$HOST_CXX" <<EOF
#!/bin/sh
export PATH="$bootstrap_sysroot/usr/bin:$bootstrap_sysroot/bin:\$PATH"
if [ -n "\${LD_LIBRARY_PATH:-}" ]; then
  export LD_LIBRARY_PATH="$bootstrap_sysroot/usr/lib/x86_64-linux-gnu:$bootstrap_sysroot/lib/x86_64-linux-gnu:\$LD_LIBRARY_PATH"
else
  export LD_LIBRARY_PATH="$bootstrap_sysroot/usr/lib/x86_64-linux-gnu:$bootstrap_sysroot/lib/x86_64-linux-gnu"
fi
exec "$bootstrap_cxx" --sysroot="$bootstrap_sysroot" -no-pie "\$@"
EOF
  chmod +x "$HOST_CXX"
fi

(
  cd "$WORK/build"
  AR="$target_tools/ar" \
  AS="$target_tools/as" \
  LD="$target_tools/ld" \
  NM="$target_tools/nm" \
  RANLIB="$target_tools/ranlib" \
  STRIP="$target_tools/strip" \
  CC="$target_gcc" CXX="$HOST_CXX" "$WORK/source/configure" \
    --target="$TARGET_TRIPLET" \
    --prefix="$PREFIX" \
    --with-as="$target_as" \
    --with-ld="$target_ld" \
    --with-sysroot="$PREFIX/sysroot" \
    --with-pkgversion="Altitude Linux 0.1" \
    --with-bugurl="https://github.com/Complexity-ML/minibash-altitude/issues" \
    --enable-languages=c,c++ \
    --disable-bootstrap \
    --disable-decimal-float \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libsanitizer \
    --disable-libssp \
    --disable-libvtv \
    --disable-multilib \
    --disable-nls \
    --enable-shared \
    --enable-threads=posix \
    --without-isl
  make -j"$JOBS" \
    AR="$target_tools/ar" \
    AS="$target_tools/as" \
    LD="$target_tools/ld" \
    NM="$target_tools/nm" \
    RANLIB="$target_tools/ranlib" \
    STRIP="$target_tools/strip" \
    all-gcc all-target-libgcc all-target-libstdc++-v3
  make DESTDIR="$WORK/payload" install-gcc install-target-libgcc install-target-libstdc++-v3
)

ln -sf "$TARGET_TRIPLET-g++" "$WORK/payload$PREFIX/bin/g++"
ln -sf "$TARGET_TRIPLET-g++" "$WORK/payload$PREFIX/bin/c++"
install -d "$WORK/payload/usr/lib"
ln -sf "$PREFIX/$TARGET_TRIPLET/lib64/libstdc++.so" "$WORK/payload/usr/lib/libstdc++.so"
ln -sf "$PREFIX/$TARGET_TRIPLET/lib64/libstdc++.so.6.0.33" "$WORK/payload/usr/lib/libstdc++.so.6"
ln -sf "$PREFIX/$TARGET_TRIPLET/lib64/libgcc_s.so" "$WORK/payload/usr/lib/libgcc_s.so"
ln -sf "$PREFIX/$TARGET_TRIPLET/lib64/libgcc_s.so.1" "$WORK/payload/usr/lib/libgcc_s.so.1"

if [ -d "$PREFIX/bin" ]; then
  cp -a "$WORK/payload$PREFIX/." "$PREFIX/"
  ln -sf "$TARGET_TRIPLET-g++" "$PREFIX/bin/g++"
  ln -sf "$TARGET_TRIPLET-g++" "$PREFIX/bin/c++"
fi

rm -rf "$WORK/payload$PREFIX/lib/gcc/$TARGET_TRIPLET/14.2.0/plugin/include"
find "$WORK/payload$PREFIX" -type f -perm -0100 \
  -exec "$toolchain_path/bin/$TARGET_TRIPLET-strip" --strip-unneeded {} + \
  2>/dev/null || true

{
  echo "Source: gcc"
  echo "Version: 14.2.0"
  echo "SHA256: $(sha256sum "$GCC_TARBALL" | awk '{print $1}')"
  echo "GMP-SHA256: $(sha256sum "$GMP_TARBALL" | awk '{print $1}')"
  echo "MPFR-SHA256: $(sha256sum "$MPFR_TARBALL" | awk '{print $1}')"
  echo "MPC-SHA256: $(sha256sum "$MPC_TARBALL" | awk '{print $1}')"
  echo "Target: $TARGET_TRIPLET"
  echo "Stage: cxx"
  echo "Bootstrap-CXX: $HOST_CXX_VERSION"
  if [ -n "${ALTITUDE_BOOTSTRAP_CXX_SYSROOT:-}" ]; then
    echo "Bootstrap-CXX-Sysroot: ${ALTITUDE_BOOTSTRAP_CXX_SYSROOT%/}"
    echo "Bootstrap-CXX-Flags: --sysroot -no-pie"
  fi
} > "$WORK/payload/usr/share/altitude/sources/gcc-cxx.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/gcc-cxx/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-gcc-cxx-14.2.0-amd64.altpkg"
