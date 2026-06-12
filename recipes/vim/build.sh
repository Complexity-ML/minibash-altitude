#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/vim}"
VERSION=9.2.0000
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
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" vim)"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
PAYLOAD="$WORK/payload"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP" make; do
  command -v "$tool" >/dev/null 2>&1 ||
    { echo "vim: missing build tool: $tool" >&2; exit 1; }
done

[ -e "$SYSROOT/usr/include/curses.h" ] ||
  { echo "vim: missing ncursesw headers in $SYSROOT" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source/src"
  CC="$CC" AR="$AR" RANLIB="$RANLIB" \
  CFLAGS="-O2 -pipe -I$SYSROOT/usr/include" \
  LDFLAGS="-L$SYSROOT/usr/lib -Wl,-rpath-link,$SYSROOT/usr/lib" \
  vim_cv_toupper_broken=no \
  vim_cv_terminfo=yes \
  vim_cv_tty_group=world \
  vim_cv_getcwd_broken=no \
  vim_cv_stat_ignores_slash=no \
  vim_cv_memmove_handles_overlap=yes \
    ./configure \
      --build="$("$WORK/source/config.guess")" \
      --host="$TARGET" \
      --prefix=/usr \
      --with-features=normal \
      --enable-gui=no \
      --with-wayland=no \
      --without-x \
      --disable-gtktest \
      --disable-netbeans \
      --disable-channel \
      --disable-terminal \
      --disable-gpm \
      --disable-selinux \
      --disable-acl \
      --disable-nls \
      --with-tlib=ncursesw
  make -j"$JOBS"
  make DESTDIR="$PAYLOAD" install
)

rm -f "$PAYLOAD/usr/bin/ex" "$PAYLOAD/usr/bin/view" "$PAYLOAD/usr/bin/rvim" \
  "$PAYLOAD/usr/bin/rview" "$PAYLOAD/usr/bin/vimdiff" "$PAYLOAD/usr/bin/vimtutor"
ln -sf vim "$PAYLOAD/usr/bin/vi"
ln -sf vim "$PAYLOAD/usr/bin/view"

find "$PAYLOAD/usr/bin" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done

install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: vim"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: terminal-only Vim cross $TARGET with ncursesw"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/vim.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/vim/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-vim-$VERSION-amd64.altpkg"
