#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/meson}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
PREFIX="/opt/altitude/forge"
VERSION=1.11.1
PYTHON="$FORGE_ROOT$PREFIX/bin/python3"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" meson)"

[ -x "$PYTHON" ] || {
  echo "meson: Altitude Python build runtime missing: $PYTHON" >&2
  exit 1
}

rm -rf "$WORK"
mkdir -p "$WORK/source" "$WORK/payload$PREFIX/bin" \
  "$WORK/payload$PREFIX/lib/meson" "$WORK/payload$PREFIX/share/man/man1" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

cp "$WORK/source/meson.py" "$WORK/payload$PREFIX/lib/meson/"
cp -a "$WORK/source/mesonbuild" "$WORK/payload$PREFIX/lib/meson/"
install -m644 "$WORK/source/man/meson.1" \
  "$WORK/payload$PREFIX/share/man/man1/meson.1"

cat > "$WORK/payload$PREFIX/bin/meson" <<EOF
#!/usr/bin/env bash
exec "$PREFIX/bin/python3" "$PREFIX/lib/meson/meson.py" "\$@"
EOF
chmod 755 "$WORK/payload$PREFIX/bin/meson"

{
  echo "Source: meson"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: source installation using Altitude forge Python"
  echo "Python: $("$PYTHON" --version 2>&1)"
} > "$WORK/payload/usr/share/altitude/sources/meson.build"

PYTHONPATH="$WORK/payload$PREFIX/lib/meson" \
  "$PYTHON" "$WORK/payload$PREFIX/lib/meson/meson.py" --version |
  grep -qx "$VERSION"

if [ -d "$PREFIX/bin" ]; then
  cp -a "$WORK/payload$PREFIX/." "$PREFIX/"
fi

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/meson/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-meson-$VERSION-amd64.altpkg"
