#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-/}"
OUT="${2:-$ROOT/out/system-packages}"
BUILDER="${ALTITUDE_ALTPKG_BUILD:-$ROOT/rootfs/bin/altpkg-build}"

[ -d "$SOURCE" ] || { echo "missing rootfs: $SOURCE" >&2; exit 1; }
[ -x "$BUILDER" ] || { echo "missing altpkg-build: $BUILDER" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
payload="$work/altitude-firmware/payload"
mkdir -p "$payload" "$OUT"

cat > "$work/altitude-firmware/MANIFEST" <<'EOF'
Format: altitude-package-1
Name: altitude-firmware
Version: 0.1.0
Architecture: all
Description: Altitude hardware firmware collection
EOF

copy_path() {
  local path="$1"
  [ -e "$SOURCE/$path" ] || [ -L "$SOURCE/$path" ] || return 0
  mkdir -p "$payload/$(dirname "$path")"
  (cd "$SOURCE" && tar -cf - "$path") | (cd "$payload" && tar -xf -)
}

copy_path usr/lib/firmware
copy_path usr/lib/crda

bash "$BUILDER" "$work/altitude-firmware/MANIFEST" "$payload" \
  "$OUT/altitude-firmware-0.1.0-all.altpkg"

echo "Altitude firmware package: $OUT/altitude-firmware-0.1.0-all.altpkg"
