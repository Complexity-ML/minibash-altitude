#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/gtk4}"
VERSION=4.20.3
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
CXX="$TOOLCHAIN/bin/$TARGET-g++"
AR="$TOOLCHAIN/bin/$TARGET-ar"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
PKG_CONFIG="$FORGE/bin/pkg-config"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" gtk4)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$CXX" "$AR" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || {
    echo "gtk4: missing build tool: $tool" >&2
    exit 1
  }
done
for tool in meson ninja awk sed; do
  command -v "$tool" >/dev/null ||
    { echo "gtk4: missing host build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

# Altitude currently ships the last Rust-free librsvg branch. GTK already has
# fallback rendering code for it; this keeps symbolic SVG CSS optional too.
sed -i "s/\\['>= 2\\.40\\.23', '< 2\\.41'\\]/['>= 2.40.21', '< 2.41']/" \
  "$WORK/source/meson.build"
awk '
  { print }
  /#include <librsvg\/rsvg.h>/ {
    print ""
    print "#if !LIBRSVG_CHECK_VERSION (2,48,0)"
    print "#define rsvg_handle_set_stylesheet(handle, stylesheet, len, error) TRUE"
    print "#endif"
  }
' "$WORK/source/gtk/gdktextureutils.c" > "$WORK/gdktextureutils.c"
mv "$WORK/gdktextureutils.c" "$WORK/source/gtk/gdktextureutils.c"

cat > "$WORK/cross.ini" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
pkg-config = '$PKG_CONFIG'

[properties]
sys_root = '$SYSROOT'
pkg_config_libdir = '$PKG_CONFIG_LIBDIR'
needs_exe_wrapper = true

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[built-in options]
c_args = ['-O2', '-pipe']
cpp_args = ['-O2', '-pipe']
c_link_args = ['-Wl,-rpath-link,$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib64', '-Wl,-rpath-link,$WORK/build/gtk']
cpp_link_args = ['-Wl,-rpath-link,$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib64', '-Wl,-rpath-link,$WORK/build/gtk']
EOF

meson setup "$WORK/build" "$WORK/source" \
  --cross-file "$WORK/cross.ini" --prefix=/usr --libdir=lib \
  --buildtype=release --default-library=shared --wrap-mode=nofallback \
  -Dbuild-tests=false -Dbuild-testsuite=false \
  -Dbuild-examples=false -Dbuild-demos=false \
  -Ddocumentation=false -Dintrospection=disabled \
  -Dx11-backend=false -Dwayland-backend=true \
  -Dbroadway-backend=false -Dvulkan=disabled \
  -Dmedia-gstreamer=disabled -Dprint-cups=disabled
meson compile -C "$WORK/build"
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/libgtk-4.so.* \
  "$PAYLOAD"/usr/lib/libgdk-4.so.* 2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: gtk4"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Meson shared Wayland cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/gtk4.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/gtk4/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-gtk4-$VERSION-amd64.altpkg"
