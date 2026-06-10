#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/systemd}"
VERSION=257.13
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
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" systemd)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || { echo "systemd: missing build tool: $tool" >&2; exit 1; }
done
for tool in meson ninja gperf; do
  command -v "$tool" >/dev/null ||
    { echo "systemd: missing host build tool: $tool" >&2; exit 1; }
done
for dep in dbus-1 libcap libxcrypt libpcre2-8 mount; do
  "$PKG_CONFIG" --exists "$dep" ||
    { echo "systemd: target dependency missing: $dep" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1
cat > "$WORK/altitude-ln-relative" <<'EOF'
#!/usr/bin/env sh
set -eu
src="$1"
dst="$2"
mkdir -p "$(dirname "$dst")"
rel="$(python3 - "$src" "$dst" <<'PY'
import os
import sys

src, dst = sys.argv[1], sys.argv[2]
print(os.path.relpath(src, os.path.dirname(dst)))
PY
)"
ln -sfn "$rel" "$dst"
EOF
chmod +x "$WORK/altitude-ln-relative"
sed -i "/relative_source_path = run_command('realpath'/,/check : true).stdout().strip()/c\\relative_source_path = '../source'" \
  "$WORK/source/meson.build"
sed -i "s/SYSTEMD_TEST_DATA=%q\\\\nSYSTEMD_CATALOG_DIR=%q\\\\n/SYSTEMD_TEST_DATA=%s\\\\nSYSTEMD_CATALOG_DIR=%s\\\\n/" \
  "$WORK/source/meson.build"
sed -i "s|^ln_s = .*|ln_s = '$WORK/altitude-ln-relative \"\${DESTDIR:-}@0@\" \"\${DESTDIR:-}@1@\"'|" \
  "$WORK/source/meson.build"
sed -i "/meson.add_install_script(sh, '-c', ln_s.format(pkgsysconfdir \\/ 'user',/,/sysconfdir \\/ 'xdg\\/systemd\\/user'))/d" \
  "$WORK/source/src/core/meson.build"
sed -i "/meson.add_install_script(sh, '-c', ln_s.format(libexecdir \\/ 'systemd', sbindir \\/ 'init'))/d" \
  "$WORK/source/src/core/meson.build"

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
c_link_args = ['-Wl,-rpath-link,$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib64', '-Wl,-rpath-link,$SYSROOT/lib', '-Wl,-rpath-link,$SYSROOT/lib64']
EOF

meson setup "$WORK/build" "$WORK/source" \
  --cross-file="$WORK/cross.ini" --prefix=/usr --libdir=lib \
  --sysconfdir=/etc --localstatedir=/var --buildtype=release \
  --wrap-mode=nofallback \
  -Dmode=release -Dtests=false -Dman=disabled -Dhtml=disabled \
  -Dtranslations=false -Dfirstboot=false -Dhibernate=false \
  -Dldconfig=false -Defi=false -Dtpm=false -Denvironment-d=false \
  -Dbinfmt=false -Drepart=disabled -Dcoredump=false -Doomd=false \
  -Dlogind=false -Dmachined=false -Dportabled=false -Duserdb=false \
  -Dhomed=disabled -Dnetworkd=false -Ddefault-network=false \
  -Dtimesyncd=false -Dnss-myhostname=false -Dnss-mymachines=disabled \
  -Dnss-resolve=disabled -Dnss-systemd=false -Dsysusers=true \
  -Dtmpfiles=true -Dutmp=false -Dwheel-group=false -Dgshadow=false \
  -Dselinux=disabled -Dapparmor=disabled -Dacl=disabled -Daudit=disabled \
  -Dblkid=enabled -Dkmod=disabled -Dpam=disabled -Dmicrohttpd=disabled \
  -Dlibcryptsetup=disabled -Dlibcryptsetup-plugins=disabled \
  -Dqrencode=disabled -Dgcrypt=disabled -Dgnutls=disabled \
  -Dopenssl=disabled -Dtpm2=disabled -Dzlib=disabled -Dbzip2=disabled \
  -Dxz=disabled -Dlz4=disabled -Dzstd=disabled -Dpcre2=enabled \
  -Dglib=disabled -Ddbus=enabled -Dbootloader=disabled

DESTDIR="$PAYLOAD" meson install -C "$WORK/build"
if [ -d "$PAYLOAD$SYSROOT/usr/share/dbus-1" ]; then
  mkdir -p "$PAYLOAD/usr/share/dbus-1"
  cp -a "$PAYLOAD$SYSROOT/usr/share/dbus-1/." "$PAYLOAD/usr/share/dbus-1/"
  rm -rf "$PAYLOAD/opt"
fi
mkdir -p "$PAYLOAD/etc/xdg/systemd" "$PAYLOAD/usr/sbin"
ln -sfn ../../systemd/user "$PAYLOAD/etc/xdg/systemd/user"
ln -sfn ../lib/systemd/systemd "$PAYLOAD/usr/sbin/init"

find "$PAYLOAD/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done

install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: systemd"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: service manager tools, tmpfiles, sysusers; optional daemons disabled"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/systemd.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/systemd/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-systemd-$VERSION-amd64.altpkg"
