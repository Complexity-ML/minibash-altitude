#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/cantarell-fonts}"
VERSION=0.303.1
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN_ROOT/opt/altitude/toolchain/sysroot"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" cantarell-fonts)"

export PATH="$FORGE/bin:$SYSROOT/usr/bin:$PATH"

for tool in meson ninja; do
  command -v "$tool" >/dev/null || { echo "cantarell-fonts: missing build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

meson setup "$WORK/build" "$WORK/source" \
  --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Duseprebuilt=true -Dbuildappstream=false
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"
{
  echo "Source: cantarell-fonts"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Meson prebuilt GNOME interface font"
} > "$PAYLOAD/usr/share/altitude/sources/cantarell-fonts.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/cantarell-fonts/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-cantarell-fonts-$VERSION-all.altpkg"
