#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/util-linux}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
VERSION=2.41.2
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
PKG_CONFIG="$FORGE/bin/pkg-config"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" util-linux)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP" "$PKG_CONFIG" make; do
  command -v "$tool" >/dev/null || { echo "util-linux: missing build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

BUILD_TRIPLET="$("$WORK/source/config/config.guess")"
(
  cd "$WORK/source"
  CC="$CC" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" PKG_CONFIG="$PKG_CONFIG" \
    LDFLAGS="-Wl,-rpath-link,$SYSROOT/usr/lib -Wl,-rpath-link,$SYSROOT/usr/lib64" \
    ./configure --build="$BUILD_TRIPLET" --host="$TARGET" \
      --prefix=/usr --libdir=/usr/lib --disable-all-programs \
      --enable-libblkid --enable-libuuid --enable-libmount --enable-mount \
      --disable-makeinstall-chown --disable-makeinstall-setuid \
      --disable-makeinstall-tty-setgid --without-python \
      --disable-nls --without-systemd --without-systemdsystemunitdir \
      --without-tinfo --without-ncursesw --without-ncurses --without-readline \
      --without-libmagic --without-selinux --without-audit --without-udev
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

find "$PAYLOAD/usr/lib" -name '*.la' -delete
"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/libblkid.so.* \
  "$PAYLOAD"/usr/lib/libuuid.so.* "$PAYLOAD"/usr/lib/libmount.so.* 2>/dev/null || true
install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: util-linux"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: minimal libblkid/libuuid/libmount/mount cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/util-linux.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/util-linux/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-util-linux-$VERSION-amd64.altpkg"
