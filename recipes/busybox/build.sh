#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/busybox}"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" busybox)"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
COMPILER="${CC:-cc}"

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/payload/usr/libexec/altitude" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

make -C "$WORK/source" defconfig >/dev/null
set_config() {
  local symbol="$1" value="$2" config="$WORK/source/.config"
  sed -i "/^CONFIG_${symbol}=/d;/^# CONFIG_${symbol} is not set/d" "$config"
  if [ "$value" = y ]; then
    echo "CONFIG_${symbol}=y" >> "$config"
  else
    echo "# CONFIG_${symbol} is not set" >> "$config"
  fi
}
set_config STATIC y
set_config FEATURE_SH_STANDALONE y
set_config FEATURE_PREFER_APPLETS y
set_config TC n
set_config FEATURE_TC_INGRESS n
make -C "$WORK/source" -j"$JOBS"

install -m 755 "$WORK/source/busybox" \
  "$WORK/payload/usr/libexec/altitude/busybox"
{
  echo "Source: busybox"
  echo "Version: 1.37.0"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: static"
  echo "Compiler: $("$COMPILER" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/busybox.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/busybox/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-busybox-1.37.0-amd64.altpkg"
