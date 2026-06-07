#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/forge-jinja2}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
PREFIX="/opt/altitude/forge"
PYTHON="$FORGE_ROOT$PREFIX/bin/python3"
PAYLOAD="$WORK/payload"
JINJA_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" jinja2)"
MARKUPSAFE_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" markupsafe)"
VERSION=3.1.6

[ -x "$PYTHON" ] || { echo "forge-jinja2: missing forge Python: $PYTHON" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/jinja2" "$WORK/markupsafe" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$JINJA_TARBALL" -C "$WORK/jinja2" --strip-components=1
tar -xf "$MARKUPSAFE_TARBALL" -C "$WORK/markupsafe" --strip-components=1

purelib="$("$PYTHON" - <<'PY'
import sysconfig
print(sysconfig.get_paths()["purelib"])
PY
)"
case "$purelib" in
  "$PREFIX"/*) payload_purelib="$PAYLOAD$purelib" ;;
  *) echo "forge-jinja2: unexpected purelib path: $purelib" >&2; exit 1 ;;
esac
install -d "$payload_purelib"
cp -a "$WORK/jinja2/src/jinja2" "$payload_purelib/"
cp -a "$WORK/markupsafe/src/markupsafe" "$payload_purelib/"

PYTHONPATH="$payload_purelib" "$PYTHON" - <<'PY'
import jinja2
import markupsafe
print(jinja2.__version__)
PY

if [ -d "$FORGE_ROOT$PREFIX" ]; then
  cp -a "$PAYLOAD$PREFIX/." "$FORGE_ROOT$PREFIX/"
fi

{
  echo "Source: jinja2"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$JINJA_TARBALL" | awk '{print $1}')"
  echo "Source: markupsafe"
  echo "MarkupSafe-Version: 3.0.3"
  echo "MarkupSafe-SHA256: $(sha256sum "$MARKUPSAFE_TARBALL" | awk '{print $1}')"
  echo "Build: pure Python modules installed into Altitude forge"
  echo "Python: $("$PYTHON" --version 2>&1)"
} > "$PAYLOAD/usr/share/altitude/sources/forge-jinja2.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/forge-jinja2/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-forge-jinja2-$VERSION-amd64.altpkg"
