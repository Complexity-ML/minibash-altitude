#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/mutter}"
VERSION=48.8
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
EXE_WRAPPER="${ALTITUDE_EXE_WRAPPER:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
PKG_CONFIG="$FORGE/bin/pkg-config"
PAYLOAD="$WORK/payload"
BUILD_TOOLS="$WORK/build-tools"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" mutter)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export LDFLAGS="${LDFLAGS:-} -Wl,-rpath-link,$SYSROOT/usr/lib -Wl,-rpath-link,$SYSROOT/usr/lib64 -Wl,-rpath-link,$SYSROOT/lib -Wl,-rpath-link,$SYSROOT/lib64 -Wl,-rpath-link,$WORK/build/cogl/cogl -Wl,-rpath-link,$WORK/build/clutter/clutter -Wl,-rpath-link,$WORK/build/mtk/mtk -L$SYSROOT/usr/lib -L$SYSROOT/usr/lib64 -L$SYSROOT/lib -L$SYSROOT/lib64 -L$WORK/build/cogl/cogl -L$WORK/build/clutter/clutter -L$WORK/build/mtk/mtk"

for tool in "$CC" "$AR" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || { echo "mutter: missing build tool: $tool" >&2; exit 1; }
done
for tool in meson ninja wayland-scanner g-ir-scanner g-ir-compiler; do
  command -v "$tool" >/dev/null ||
    { echo "mutter: missing forge tool: $tool" >&2; exit 1; }
done
for dep in graphene-gobject-1.0 gdk-pixbuf-2.0 cairo pixman-1 \
  gsettings-desktop-schemas glib-2.0 gio-unix-2.0 gobject-2.0 \
  gmodule-no-export-2.0 xkbcommon atk colord lcms2 libeis-1.0 libei-1.0 \
  libdisplay-info pango pangocairo harfbuzz fribidi gtk4 gnome-desktop-4 \
  egl glesv2 wayland-server wayland-client wayland-cursor \
  wayland-protocols wayland-egl libudev gudev-1.0 udev gbm libinput libdrm \
  libelogind gobject-introspection-1.0; do
  "$PKG_CONFIG" --exists "$dep" ||
    { echo "mutter: target dependency missing from $SYSROOT: $dep" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$BUILD_TOOLS" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1
sed -i "s/subdir('doc\\/man')/# Altitude: manpages need rst2man, skip for source build/" \
  "$WORK/source/meson.build"
sed -i '/#include "meta\/prefs.h"/a\
\
#ifndef ATK_LIVE_POLITE\
#define ATK_LIVE_POLITE "polite"\
#endif' "$WORK/source/src/core/workspace.c"
perl -0pi -e 's/  if \(!stage_accessible\)\n    return;/  if (!stage_accessible ||\n      g_signal_lookup ("notification", G_OBJECT_TYPE (stage_accessible)) == 0)\n    return;/' \
  "$WORK/source/src/core/workspace.c"

cat > "$BUILD_TOOLS/ldd" <<EOF
#!/usr/bin/env sh
exec "$SYSROOT/usr/lib/ld-linux-x86-64.so.2" --list "\$@"
EOF
chmod 755 "$BUILD_TOOLS/ldd"
export PATH="$BUILD_TOOLS:$PATH"

if [ -z "$EXE_WRAPPER" ]; then
  EXE_WRAPPER="$WORK/target-wrapper"
  cat > "$EXE_WRAPPER" <<EOF
#!/usr/bin/env sh
export LD_LIBRARY_PATH="$SYSROOT/usr/lib:$SYSROOT/usr/lib64:$SYSROOT/lib:$SYSROOT/lib64:$FORGE/lib:\${LD_LIBRARY_PATH:-}"
exec "\$@"
EOF
  chmod 755 "$EXE_WRAPPER"
fi

cat > "$WORK/cross.ini" <<EOF
[binaries]
c = '$CC'
ar = '$AR'
strip = '$STRIP'
pkg-config = '$PKG_CONFIG'
exe_wrapper = '$EXE_WRAPPER'

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
c_link_args = ['-Wl,-rpath-link,$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib64', '-Wl,-rpath-link,$SYSROOT/lib', '-Wl,-rpath-link,$SYSROOT/lib64', '-Wl,-rpath-link,$WORK/build/cogl/cogl', '-Wl,-rpath-link,$WORK/build/clutter/clutter', '-Wl,-rpath-link,$WORK/build/mtk/mtk']
EOF

meson setup "$WORK/build" "$WORK/source" \
  --cross-file="$WORK/cross.ini" --prefix=/usr --libdir=lib \
  --buildtype=release --wrap-mode=nofallback \
  -Dopengl=false -Dgles2=true -Degl=true -Dglx=false \
  -Dwayland=true -Dxwayland=false -Dx11=false \
  -Dlogind=true -Dnative_backend=true -Dremote_desktop=false \
  -Dlibgnome_desktop=true -Dudev=true -Dlibwacom=false \
  -Dsound_player=false -Dstartup_notification=false -Dsm=false \
  -Dintrospection=true -Ddocs=false -Dtests=disabled \
  -Dcogl_tests=false -Dclutter_tests=false -Dmutter_tests=false \
  -Dprofiler=false -Dinstalled_tests=false -Dfonts=true \
  -Dbash_completion=false
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

if [ -d "$PAYLOAD/usr/lib/mutter-16" ]; then
  for lib in "$PAYLOAD"/usr/lib/mutter-16/libmutter-*.so*; do
    [ -e "$lib" ] || continue
    ln -sf "mutter-16/$(basename "$lib")" "$PAYLOAD/usr/lib/$(basename "$lib")"
  done
fi

find "$PAYLOAD/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done
install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: mutter"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: native Wayland EGL/GLES2, no X11/Xwayland/systemd, cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/mutter.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/mutter/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-mutter-$VERSION-amd64.altpkg"
