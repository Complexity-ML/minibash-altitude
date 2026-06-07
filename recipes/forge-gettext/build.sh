#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/forge-gettext}"
PREFIX="/opt/altitude/forge"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
TARGET="${ALTITUDE_TARGET:-x86_64-altitude-linux-gnu}"
COMPILER="${CC:-}"
if [ -z "$COMPILER" ]; then
  if command -v cc >/dev/null 2>&1; then
    COMPILER=cc
  elif command -v "$TARGET-gcc" >/dev/null 2>&1; then
    COMPILER="$TARGET-gcc"
  else
    COMPILER=gcc
  fi
fi
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" gettext)"
GETTEXT_CFLAGS="${CFLAGS:-} -std=gnu17 -Wno-incompatible-pointer-types"

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/payload$PREFIX" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

(
  cd "$WORK/source"
  CC="$COMPILER" CFLAGS="$GETTEXT_CFLAGS" ./configure --prefix="$PREFIX" \
    --disable-shared --disable-java --disable-native-java \
    --disable-csharp --disable-c++ --without-emacs --without-git \
    --without-cvs --without-libtextstyle-prefix --disable-openmp \
    --disable-acl
  make -j"$JOBS"
  make DESTDIR="$WORK/payload" install
)

find "$WORK/payload$PREFIX" -type f -perm -0100 -exec strip --strip-unneeded {} + 2>/dev/null || true

{
  echo "Source: gettext"
  echo "Version: 0.26"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: native forge gettext tools"
  echo "CFLAGS: $GETTEXT_CFLAGS"
  echo "Compiler: $("$COMPILER" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/forge-gettext.build"

if [ -d "$PREFIX" ]; then
  cp -a "$WORK/payload$PREFIX/." "$PREFIX/"
fi

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/forge-gettext/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-forge-gettext-0.26-amd64.altpkg"
