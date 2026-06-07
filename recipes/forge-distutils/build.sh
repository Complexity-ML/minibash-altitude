#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/forge-distutils}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
PREFIX="/opt/altitude/forge"
PYTHON="$FORGE_ROOT$PREFIX/bin/python3"
PAYLOAD="$WORK/payload"
TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" setuptools)"
VERSION=68.2.2

[ -x "$PYTHON" ] || { echo "forge-distutils: missing forge Python: $PYTHON" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/source" "$PAYLOAD/usr/share/altitude/sources" "$OUT"
tar -xf "$TARBALL" -C "$WORK/source" --strip-components=1

purelib="$("$PYTHON" - <<'PY'
import sysconfig
print(sysconfig.get_paths()["purelib"])
PY
)"
case "$purelib" in
  "$PREFIX"/*) payload_purelib="$PAYLOAD$purelib" ;;
  *) echo "forge-distutils: unexpected purelib path: $purelib" >&2; exit 1 ;;
esac

install -d "$payload_purelib"
cp -a "$WORK/source/setuptools/_distutils" "$payload_purelib/distutils"

PYTHONPATH="$payload_purelib" "$PYTHON" - <<'PY'
import distutils
import distutils.ccompiler
import distutils.cygwinccompiler
import distutils.sysconfig
import distutils.unixccompiler
print(distutils.__file__)
PY

if [ -d "$FORGE_ROOT$PREFIX" ]; then
  cp -a "$PAYLOAD$PREFIX/." "$FORGE_ROOT$PREFIX/"
fi

{
  echo "Source: setuptools"
  echo "Version: $VERSION"
  echo "SHA256: $(sha256sum "$TARBALL" | awk '{print $1}')"
  echo "Build: copy setuptools._distutils as distutils for forge Python"
  echo "Python: $("$PYTHON" --version 2>&1)"
} > "$PAYLOAD/usr/share/altitude/sources/forge-distutils.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/forge-distutils/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-forge-distutils-$VERSION-amd64.altpkg"
