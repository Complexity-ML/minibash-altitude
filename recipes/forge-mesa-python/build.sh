#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/forge-mesa-python}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
PREFIX=/opt/altitude/forge
PYTHON="$FORGE_ROOT$PREFIX/bin/python3"
ABI=3.13
SITE="$PREFIX/lib/python$ABI/site-packages"
MAKO_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" mako)"
PYYAML_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" pyyaml)"
MARKUPSAFE_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" markupsafe)"
PACKAGING_TARBALL="$(bash "$ROOT/scripts/source-fetch.sh" packaging)"

[ -x "$PYTHON" ] || {
  echo "forge-mesa-python: Altitude Python missing: $PYTHON" >&2
  exit 1
}

rm -rf "$WORK"
mkdir -p "$WORK/mako" "$WORK/pyyaml" "$WORK/markupsafe" \
  "$WORK/packaging" \
  "$WORK/payload$SITE" "$WORK/payload/usr/share/altitude/sources" "$OUT"
tar -xf "$MAKO_TARBALL" -C "$WORK/mako" --strip-components=1
tar -xf "$PYYAML_TARBALL" -C "$WORK/pyyaml" --strip-components=1
tar -xf "$MARKUPSAFE_TARBALL" -C "$WORK/markupsafe" --strip-components=1
tar -xf "$PACKAGING_TARBALL" -C "$WORK/packaging" --strip-components=1

find_package_dir() {
  local root="$1" package="$2"
  local found
  found=""
  for candidate in "$root/src/$package" "$root/lib/$package" "$root/$package"; do
    if [ -f "$candidate/__init__.py" ]; then
      found="$candidate"
      break
    fi
  done
  if [ -z "$found" ]; then
    found="$(find "$root" -type f -path "*/$package/__init__.py" -print -quit)"
    found="${found%/__init__.py}"
  fi
  [ -n "$found" ] || {
    echo "forge-mesa-python: package directory not found: $package" >&2
    exit 1
  }
  printf '%s\n' "$found"
}

cp -a "$(find_package_dir "$WORK/mako" mako)" "$WORK/payload$SITE/"
cp -a "$(find_package_dir "$WORK/pyyaml" yaml)" "$WORK/payload$SITE/"
cp -a "$(find_package_dir "$WORK/markupsafe" markupsafe)" "$WORK/payload$SITE/"
cp -a "$(find_package_dir "$WORK/packaging" packaging)" "$WORK/payload$SITE/"

PYTHONPATH="$WORK/payload$SITE" "$PYTHON" -c \
  'import mako, markupsafe, packaging, yaml; print("mesa-python-modules-ok")'

{
  echo "Source: mako, pyyaml, markupsafe, packaging"
  echo "Mako-SHA256: $(sha256sum "$MAKO_TARBALL" | awk '{print $1}')"
  echo "PyYAML-SHA256: $(sha256sum "$PYYAML_TARBALL" | awk '{print $1}')"
  echo "MarkupSafe-SHA256: $(sha256sum "$MARKUPSAFE_TARBALL" | awk '{print $1}')"
  echo "Packaging-SHA256: $(sha256sum "$PACKAGING_TARBALL" | awk '{print $1}')"
  echo "Build: pure Python modules for Mesa code generation"
  echo "Python: $("$PYTHON" --version 2>&1)"
} > "$WORK/payload/usr/share/altitude/sources/forge-mesa-python.build"

if [ -d "$FORGE_ROOT$PREFIX/lib/python$ABI/site-packages" ]; then
  cp -a "$WORK/payload$SITE/." "$FORGE_ROOT$SITE/"
fi

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/forge-mesa-python/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-forge-mesa-python-1.0.0-amd64.altpkg"
