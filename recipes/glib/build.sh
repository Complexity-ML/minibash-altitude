#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/glib}"
VERSION=2.84.4
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
EXE_WRAPPER="${ALTITUDE_EXE_WRAPPER:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
SYSROOT="$TOOLCHAIN/sysroot"
FORGE="$FORGE_ROOT/opt/altitude/forge"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
PKG_CONFIG="$FORGE/bin/pkg-config"
BUILD_TOOLS="$WORK/build-tools"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" glib)"

for tool in "$CC" "$AR" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || { echo "glib: missing build tool: $tool" >&2; exit 1; }
done
export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
for tool in meson ninja g-ir-scanner g-ir-compiler; do
  command -v "$tool" >/dev/null ||
    { echo "glib: missing host build tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$WORK/payload/usr/share/altitude/sources" "$BUILD_TOOLS" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

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
pkg_config_libdir = '$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/lib64/pkgconfig:$SYSROOT/usr/share/pkgconfig'
needs_exe_wrapper = true

[built-in options]
c_link_args = ['-Wl,-rpath-link,$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib64']

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/lib64/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export LDFLAGS="${LDFLAGS:-} -Wl,-rpath-link,$SYSROOT/usr/lib -Wl,-rpath-link,$SYSROOT/usr/lib64 -L$SYSROOT/usr/lib -L$SYSROOT/usr/lib64"
"$PKG_CONFIG" --exists libffi ||
  { echo "glib: target libffi is missing from $SYSROOT" >&2; exit 1; }
"$PKG_CONFIG" --exists libpcre2-8 ||
  { echo "glib: target PCRE2 is missing from $SYSROOT" >&2; exit 1; }
meson setup "$WORK/build" "$WORK/source" \
  --cross-file="$WORK/cross.ini" \
  --prefix=/usr \
  --libdir=lib \
  --buildtype=release \
  --wrap-mode=nofallback \
  -Ddefault_library=both \
  -Dintrospection=enabled \
  -Dglib_debug=disabled \
  -Dman-pages=disabled \
  -Dtests=false \
  -Dinstalled_tests=false \
  -Dsysprof=disabled \
  -Dlibmount=disabled \
  -Dselinux=disabled \
  -Dxattr=false
DESTDIR="$WORK/payload" ninja -C "$WORK/build" -j"$JOBS" install

find "$WORK/payload/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done

install -d "$SYSROOT/usr/include" "$SYSROOT/usr/lib" "$SYSROOT/usr/share"
cp -a "$WORK/payload/usr/include/." "$SYSROOT/usr/include/"
cp -a "$WORK/payload/usr/lib/." "$SYSROOT/usr/lib/"
cp -a "$WORK/payload/usr/share/glib-2.0" "$SYSROOT/usr/share/"
[ -d "$WORK/payload/usr/share/gir-1.0" ] && \
  cp -a "$WORK/payload/usr/share/gir-1.0" "$SYSROOT/usr/share/"
if [ -d "$WORK/payload/usr/bin" ]; then
  install -d "$FORGE/bin"
  cp -a "$WORK/payload/usr/bin/." "$FORGE/bin/"
fi
install -d "$FORGE/share"
cp -a "$WORK/payload/usr/share/glib-2.0" "$FORGE/share/"
[ -d "$WORK/payload/usr/share/gir-1.0" ] && \
  cp -a "$WORK/payload/usr/share/gir-1.0" "$FORGE/share/"
FORGE_PC_BIN='${pc_sysrootdir}/../../forge/bin'
for pcdir in "$WORK/payload/usr/lib/pkgconfig" "$SYSROOT/usr/lib/pkgconfig"; do
  for pc in "$pcdir/glib-2.0.pc" "$pcdir/gio-2.0.pc"; do
    [ -f "$pc" ] || continue
    sed -i \
      -e "s|^glib_genmarshal=.*|glib_genmarshal=$FORGE_PC_BIN/glib-genmarshal|" \
      -e "s|^glib_mkenums=.*|glib_mkenums=$FORGE_PC_BIN/glib-mkenums|" \
      -e "s|^glib_compile_schemas=.*|glib_compile_schemas=$FORGE_PC_BIN/glib-compile-schemas|" \
      -e "s|^glib_compile_resources=.*|glib_compile_resources=$FORGE_PC_BIN/glib-compile-resources|" \
      -e "s|^gdbus_codegen=.*|gdbus_codegen=$FORGE_PC_BIN/gdbus-codegen|" \
      "$pc"
  done
done

{
  echo "Source: glib"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: shared+static cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
  echo "Meson: $(meson --version)"
} > "$WORK/payload/usr/share/altitude/sources/glib.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/glib/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-glib-$VERSION-amd64.altpkg"
