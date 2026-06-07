#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/wayland}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
VERSION=1.25.0
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" wayland)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
BUILD_CC="$TOOLCHAIN/bin/$TARGET-gcc"
BUILD_AR="$TOOLCHAIN/bin/$TARGET-ar"
BUILD_STRIP="$TOOLCHAIN/bin/$TARGET-strip"

for tool in meson ninja pkg-config "$TARGET-gcc"; do
  command -v "$tool" >/dev/null || {
    echo "wayland: missing Altitude forge tool: $tool" >&2
    exit 1
  }
done
pkg-config --exists libffi || {
  echo "wayland: target libffi is missing from $SYSROOT" >&2
  exit 1
}

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/native-build" "$WORK/target-build" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

cat > "$WORK/altitude-cross.ini" <<EOF
[binaries]
c = '$TOOLCHAIN/bin/$TARGET-gcc'
ar = '$TOOLCHAIN/bin/$TARGET-ar'
strip = '$TOOLCHAIN/bin/$TARGET-strip'
pkg-config = '$FORGE/bin/pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[properties]
sys_root = '$SYSROOT'
EOF

# The scanner is a build-machine program used by protocol consumers.
env -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_SYSROOT_DIR \
  CC="$BUILD_CC" AR="$BUILD_AR" STRIP="$BUILD_STRIP" \
  meson setup "$WORK/native-build" "$WORK/source" \
  --prefix=/opt/altitude/forge --buildtype=release \
  -Ddocumentation=false -Dtests=false -Dlibraries=false \
  -Dscanner=true -Ddtd_validation=false
ninja -C "$WORK/native-build" src/wayland-scanner
DESTDIR="$WORK/payload" ninja -C "$WORK/native-build" install
if [ -d "$FORGE/bin" ]; then
  cp -a "$WORK/payload/opt/altitude/forge/." "$FORGE/"
fi
install -Dm755 "$WORK/payload/opt/altitude/forge/bin/wayland-scanner" \
  "$SYSROOT/opt/altitude/forge/bin/wayland-scanner"

PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig:$FORGE/lib/pkgconfig:$FORGE/lib64/pkgconfig:$FORGE/share/pkgconfig" \
meson setup "$WORK/target-build" "$WORK/source" \
  --cross-file="$WORK/altitude-cross.ini" \
  --prefix=/usr --libdir=lib --buildtype=release \
  -Ddocumentation=false -Dtests=false -Dlibraries=true \
  -Dscanner=false -Ddtd_validation=false
DESTDIR="$WORK/payload" ninja -C "$WORK/target-build" install

install -d "$SYSROOT/usr"
cp -a "$WORK/payload/usr/include" "$SYSROOT/usr/"
cp -a "$WORK/payload/usr/lib" "$SYSROOT/usr/"
cp -a "$WORK/payload/usr/share" "$SYSROOT/usr/"

{
  echo "Source: wayland"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: forge scanner plus shared target libraries"
  echo "Target: $TARGET"
  echo "Compiler: $("$TARGET-gcc" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/wayland.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/wayland/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-wayland-$VERSION-amd64.altpkg"
