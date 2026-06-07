#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/libdrm}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
VERSION=2.4.134
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" libdrm)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
for tool in meson ninja pkg-config "$TARGET-gcc"; do
  command -v "$tool" >/dev/null || {
    echo "libdrm: missing Altitude forge tool: $tool" >&2
    exit 1
  }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
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

meson setup "$WORK/build" "$WORK/source" \
  --cross-file="$WORK/altitude-cross.ini" \
  --prefix=/usr --libdir=lib --buildtype=release \
  -Dtests=false -Dudev=false -Dvalgrind=disabled \
  -Dintel=disabled -Damdgpu=enabled -Dradeon=enabled -Dnouveau=enabled \
  -Dvmwgfx=enabled -Dfreedreno=disabled -Detnaviv=disabled \
  -Dexynos=disabled -Domap=disabled -Dtegra=disabled
DESTDIR="$WORK/payload" ninja -C "$WORK/build" install

install -d "$SYSROOT/usr"
cp -a "$WORK/payload/usr/include" "$SYSROOT/usr/"
cp -a "$WORK/payload/usr/lib" "$SYSROOT/usr/"

{
  echo "Source: libdrm"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: shared DRM core, AMD, Radeon, Nouveau and VMware libraries"
  echo "Target: $TARGET"
  echo "Compiler: $("$TARGET-gcc" --version | head -1)"
} > "$WORK/payload/usr/share/altitude/sources/libdrm.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/libdrm/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-libdrm-$VERSION-amd64.altpkg"
