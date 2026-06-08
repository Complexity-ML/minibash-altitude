#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/adwaita-icon-theme}"
VERSION=48.1
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN_ROOT/opt/altitude/toolchain/sysroot"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" adwaita-icon-theme)"

export PATH="$FORGE/bin:$SYSROOT/usr/bin:$PATH"

for tool in meson ninja gtk4-update-icon-cache; do
  command -v "$tool" >/dev/null || { echo "adwaita-icon-theme: missing build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

meson setup "$WORK/build" "$WORK/source" \
  --prefix=/usr --buildtype=release --wrap-mode=nofallback
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"
{
  echo "Source: adwaita-icon-theme"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Meson icon and cursor theme data"
} > "$PAYLOAD/usr/share/altitude/sources/adwaita-icon-theme.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/adwaita-icon-theme/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-adwaita-icon-theme-$VERSION-all.altpkg"
