#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/xkeyboard-config}"
VERSION=2.45
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" xkeyboard-config)"

export PATH="$FORGE/bin:$TOOLCHAIN/bin:$PATH"

for tool in meson ninja; do
  command -v "$tool" >/dev/null ||
    { echo "xkeyboard-config: missing forge tool: $tool" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/build" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1
cat > "$WORK/source/rules/xml2lst.pl" <<'EOF'
#!/bin/sh
# Altitude does not ship Perl in the forge; GNOME consumes the XML rules.
exit 0
EOF
chmod +x "$WORK/source/rules/xml2lst.pl"

meson setup "$WORK/build" "$WORK/source" \
  --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nofallback \
  -Dnls=false -Dcompat-rules=false -Dxorg-rules-symlinks=true \
  -Dnon-latin-layouts-list=false
DESTDIR="$PAYLOAD" meson install -C "$WORK/build"

install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"
if [ -L "$SYSROOT/usr/share/X11/xkb" ]; then
  ln -sfn ../xkeyboard-config-2 "$SYSROOT/usr/share/X11/xkb"
fi
if [ -L "$PAYLOAD/usr/share/X11/xkb" ]; then
  ln -sfn ../xkeyboard-config-2 "$PAYLOAD/usr/share/X11/xkb"
fi

{
  echo "Source: xkeyboard-config"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: Meson data install for $TARGET"
} > "$PAYLOAD/usr/share/altitude/sources/xkeyboard-config.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/xkeyboard-config/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-xkeyboard-config-$VERSION-amd64.altpkg"
