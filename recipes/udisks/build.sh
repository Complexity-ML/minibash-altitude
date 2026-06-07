#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/udisks}"
VERSION=2.11.1
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
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" udisks)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG="$PKG_CONFIG"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$RANLIB" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || { echo "udisks: missing build tool: $tool" >&2; exit 1; }
done
for tool in make msgfmt; do
  command -v "$tool" >/dev/null ||
    { echo "udisks: missing host build tool: $tool" >&2; exit 1; }
done
for dep in blkid blockdev gio-unix-2.0 glib-2.0 gmodule-2.0 gudev-1.0 \
  libelogind mount polkit-agent-1 polkit-gobject-1 uuid; do
  "$PKG_CONFIG" --exists "$dep" ||
    { echo "udisks: target dependency missing: $dep" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/build"
  CC="$CC --sysroot=$SYSROOT" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" \
    CFLAGS="-O2 -pipe" \
    "$WORK/source/configure" \
      --build="$(bash "$WORK/source/build-aux/config.guess")" \
      --host="$TARGET" --prefix=/usr --libdir=/usr/lib \
      --libexecdir=/usr/libexec --sysconfdir=/etc \
      --localstatedir=/var --disable-static --disable-man \
      --disable-gtk-doc --disable-introspection \
      --disable-acl --disable-smart --disable-lvm2 \
      --disable-iscsi --disable-btrfs --disable-lsm \
      --with-systemdsystemunitdir=/usr/lib/systemd/system \
      --with-tmpfilesdir=/usr/lib/tmpfiles.d \
      --with-modloaddir=/usr/lib/modules-load.d \
      --with-modprobedir=/usr/lib/modprobe.d
  make -j"${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
  make DESTDIR="$PAYLOAD" install
)

find "$PAYLOAD/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: udisks"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Autotools core storage daemon and library cross $TARGET"
  echo "Service: /usr/libexec/udisks2/udisksd"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/udisks.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/udisks/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-udisks-$VERSION-amd64.altpkg"
