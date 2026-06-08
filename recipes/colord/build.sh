#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/colord}"
VERSION=1.4.8
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
AR="$TOOLCHAIN/bin/$TARGET-ar"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
PKG_CONFIG="$FORGE/bin/pkg-config"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" colord)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$STRIP" "$PKG_CONFIG" meson ninja; do
  command -v "$tool" >/dev/null || { echo "colord: missing build tool: $tool" >&2; exit 1; }
done
for dep in gio-2.0 glib-2.0 gmodule-2.0 gio-unix-2.0 gusb gudev-1.0 \
  libudev lcms2 polkit-gobject-1 sqlite3; do
  "$PKG_CONFIG" --exists "$dep" || { echo "colord: target dependency missing: $dep" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1
sed -i \
  -e "s/sqlite = dependency('sqlite3')/sqlite = dependency('sqlite3', required : false)/" \
  -e "s/subdir('po')/# subdir('po')/" \
  -e "s/subdir('client')/# subdir('client')/" \
  -e "s/subdir('contrib')/# subdir('contrib')/" \
  -e "s/subdir('man')/# subdir('man')/" \
  "$WORK/source/meson.build"
sed -i "/meson.add_install_script('meson_post_install.sh'/,/localstatedir, get_option('daemon_user'))/d" \
  "$WORK/source/meson.build"
sed -i "s/subdir('colorhug')/# subdir('colorhug')/" "$WORK/source/lib/meson.build"
sed -i \
  -e "s/subdir('cmf')/# subdir('cmf')/" \
  -e "s/subdir('figures')/# subdir('figures')/" \
  -e "s/subdir('illuminant')/# subdir('illuminant')/" \
  -e "s/subdir('profiles')/# subdir('profiles')/" \
  -e "s/subdir('ref')/# subdir('ref')/" \
  -e "s/subdir('tests')/# subdir('tests')/" \
  -e "s/subdir('ti1')/# subdir('ti1')/" \
  "$WORK/source/data/meson.build"
perl -0pi -e 's/\n <gresource prefix="\/org\/freedesktop\/colord\/profiles">.*?<\/gresource>\n/\n/s' \
  "$WORK/source/src/colord.gresource.xml"
sed -i \
  -e "s/subdir('plugins')/# subdir('plugins')/" \
  -e "s/subdir('sensors')/# subdir('sensors')/" \
  "$WORK/source/src/meson.build"
perl -0pi -e "s/source_dir : \\[\\n    '\\.',\\n    '\\.\\.\\/data\\/profiles',\\n  \\],/source_dir : ['.'],/s" \
  "$WORK/source/src/meson.build"
perl -0pi -e "s/,\\n  dependencies : generated_iccs//s" \
  "$WORK/source/src/meson.build"
perl -0pi -e "s/#newer polkit has the ITS rules included.*?endif/configure_file(\n  input: policy_in,\n  output: 'org.freedesktop.color.policy',\n  copy: true,\n  install: true,\n  install_dir: join_paths(datadir, 'polkit-1', 'actions')\n)/s" \
  "$WORK/source/policy/meson.build"

cat > "$WORK/cross.ini" <<EOF
[binaries]
c = '$CC'
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
c_link_args = ['-Wl,-rpath-link,$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib64']
EOF

meson setup "$WORK/build" "$WORK/source" \
  --cross-file="$WORK/cross.ini" --prefix=/usr --libdir=lib \
  --libexecdir=libexec --localstatedir=/var --sysconfdir=/etc \
  --buildtype=release --wrap-mode=nofallback \
  -Ddaemon=true -Dsession_example=false -Dbash_completion=false \
  -Dudev_rules=false -Dsystemd=false -Dargyllcms_sensor=false \
  -Dsane=false -Dintrospection=false -Dvapi=false \
  -Dprint_profiles=false -Dtests=false -Dinstalled_tests=false \
  -Dman=false -Ddocs=false
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

"$STRIP" --strip-unneeded "$PAYLOAD"/usr/lib/libcolord.so.* "$PAYLOAD"/usr/lib/libcolordprivate.so.* 2>/dev/null || true
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"
{
  echo "Source: colord"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Meson client library and D-Bus daemon cross $TARGET"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/colord.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/colord/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-colord-$VERSION-amd64.altpkg"
