#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/elogind}"
VERSION=257.16
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
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" elogind)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

for tool in "$CC" "$AR" "$STRIP" "$PKG_CONFIG"; do
  [ -x "$tool" ] || { echo "elogind: missing build tool: $tool" >&2; exit 1; }
done
for tool in meson ninja; do
  command -v "$tool" >/dev/null ||
    { echo "elogind: missing host build tool: $tool" >&2; exit 1; }
done
for dep in dbus-1 libcap libudev mount; do
  "$PKG_CONFIG" --exists "$dep" ||
    { echo "elogind: target dependency missing: $dep" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

sed -i "/relative_source_path = run_command('realpath'/,/check : true).stdout().strip()/c\\relative_source_path = '../source'" \
  "$WORK/source/meson.build"
sed -i "s/SYSTEMD_TEST_DATA=%q\\\\nSYSTEMD_CATALOG_DIR=%q\\\\n/SYSTEMD_TEST_DATA=%s\\\\nSYSTEMD_CATALOG_DIR=%s\\\\n/" \
  "$WORK/source/meson.build"
sed -i "s/if get_option('nss-elogind') != false/if true/" \
  "$WORK/source/src/shared/meson.build"
cat > "$WORK/source/tools/meson-render-jinja2.py" <<'PY'
#!/usr/bin/env python3
import ast
import os
import re
import sys

def parse_config_h(filename):
    ans = {}
    for line in open(filename):
        m = re.match(r'#define\s+(\w+)\s+(.*)', line)
        if not m:
            continue
        key, val = m.groups()
        if val and (val[0] in '123456789"' or val == '0'):
            val = ast.literal_eval(val)
        ans[key] = val
    return ans

def truthy(value):
    return bool(value) and value != '0'

def render_expr(expr, defines):
    expr = expr.strip()
    if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', expr):
        return str(defines.get(expr, ''))
    return str(eval(expr, {"__builtins__": {}}, defines))

def render_conditionals(text, defines):
    pattern = re.compile(r'{%\s*if\s+([A-Za-z_][A-Za-z0-9_]*)\s*%}(.*?){%\s*endif\s*%}', re.S)
    while True:
        match = pattern.search(text)
        if not match:
            return text
        body = match.group(2) if truthy(defines.get(match.group(1), 0)) else ''
        text = text[:match.start()] + body + text[match.end():]

def render(filename, defines):
    text = open(filename).read()
    raw_blocks = []
    def save_raw(match):
        raw_blocks.append(match.group(1))
        return f'@@ALTITUDE_RAW_{len(raw_blocks) - 1}@@'
    text = re.sub(r'{%\s*raw\s*-?%}(.*?){%\s*endraw\s*%}', save_raw, text, flags=re.S)
    text = render_conditionals(text, defines)
    text = re.sub(r'{{\s*(.*?)\s*}}', lambda m: render_expr(m.group(1), defines), text)
    for i, raw in enumerate(raw_blocks):
        text = text.replace(f'@@ALTITUDE_RAW_{i}@@', raw)
    return text

def main():
    defines = parse_config_h(sys.argv[1])
    output = render(sys.argv[2], defines)
    with open(sys.argv[3], 'w') as f:
        f.write(output)
    os.chmod(sys.argv[3], os.stat(sys.argv[2]).st_mode)

if __name__ == '__main__':
    main()
PY
chmod +x "$WORK/source/tools/meson-render-jinja2.py"

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
  --cross-file="$WORK/cross.ini" \
  --prefix=/usr --libdir=lib --libexecdir=libexec \
  --buildtype=release --default-library=both --wrap-mode=nofallback \
  -Dmode=release -Dcgroup-controller=elogind \
  -Ddbuspolicydir=/usr/share/dbus-1/system.d \
  -Ddbussystemservicedir=/usr/share/dbus-1/system-services \
  -Dudevbindir=/usr/lib/udev -Dudevrulesdir=/usr/lib/udev/rules.d \
  -Dhalt-path=/sbin/halt -Dpoweroff-path=/sbin/poweroff \
  -Dreboot-path=/sbin/reboot -Dnss-elogind=false -Duserdb=false \
  -Dvarlink=false -Defi=false -Dpam=disabled -Dacl=disabled \
  -Daudit=disabled -Dselinux=disabled -Dsmack=false \
  -Dpolkit=disabled -Ddbus=enabled -Dutmp=false \
  -Dtranslations=false -Dman=disabled -Dhtml=disabled \
  -Dtests=false -Dinstall-tests=false
meson compile -C "$WORK/build"
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

find "$PAYLOAD/usr" -type f -perm -0100 -print0 |
  while IFS= read -r -d '' file; do
    "$STRIP" --strip-unneeded "$file" 2>/dev/null || true
  done
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: elogind"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Meson login daemon and libelogind cross $TARGET"
  echo "Service: /usr/libexec/elogind"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/elogind.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/elogind/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-elogind-$VERSION-amd64.altpkg"
