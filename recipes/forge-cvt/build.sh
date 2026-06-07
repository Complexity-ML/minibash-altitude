#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/forge-cvt}"
PREFIX="/opt/altitude/forge"

rm -rf "$WORK"
mkdir -p "$WORK/payload$PREFIX/bin" \
  "$WORK/payload/usr/share/altitude/sources" "$OUT"

cat > "$WORK/payload$PREFIX/bin/cvt" <<'PY'
#!/usr/bin/env python3
import math
import sys

def usage():
    print("usage: cvt [-r] HRES VRES [VREFRESH]", file=sys.stderr)
    sys.exit(1)

def align8(value):
    return int(math.ceil(value / 8.0) * 8)

def modeline(width, height, refresh, reduced):
    if width <= 0 or height <= 0 or refresh <= 0:
        usage()

    if reduced:
        hblank = 160
        hfront = 48
        hsync = 32
        hback = hblank - hfront - hsync
        vfront = 3
        vsync = 6
        vback = 6
        hsync_flag = "+"
        vsync_flag = "-"
    else:
        hfront = align8(width * 0.05)
        hsync = align8(width * 0.04)
        hback = align8(width * 0.10)
        vfront = 3
        vsync = 5
        vback = max(10, int(round(height * 0.05)))
        hsync_flag = "-"
        vsync_flag = "+"

    hsync_start = width + hfront
    hsync_end = hsync_start + hsync
    htotal = width + hfront + hsync + hback
    vsync_start = height + vfront
    vsync_end = vsync_start + vsync
    vtotal = height + vfront + vsync + vback
    clock = htotal * vtotal * refresh / 1000000.0
    suffix = "RB" if reduced else ""
    name = f'"{width}x{height}_{refresh:.2f}{suffix}"'

    print(f"# {width}x{height} {refresh:.2f} Hz, generated for Altitude forge")
    print(
        "Modeline %s %.2f %d %d %d %d %d %d %d %d %sHSync %sVSync" %
        (name, clock, width, hsync_start, hsync_end, htotal,
         height, vsync_start, vsync_end, vtotal, hsync_flag, vsync_flag)
    )

def main(argv):
    reduced = False
    args = list(argv[1:])
    if args and args[0] == "-r":
        reduced = True
        args = args[1:]
    if len(args) not in (2, 3):
        usage()
    try:
        width = int(args[0])
        height = int(args[1])
        refresh = float(args[2]) if len(args) == 3 else 60.0
    except ValueError:
        usage()
    modeline(width, height, refresh, reduced)

if __name__ == "__main__":
    main(sys.argv)
PY
chmod 755 "$WORK/payload$PREFIX/bin/cvt"

{
  echo "Source: altitude-forge-cvt"
  echo "Version: 1.0.0"
  echo "Build: in-tree Python cvt-compatible modeline generator"
} > "$WORK/payload/usr/share/altitude/sources/forge-cvt.build"

if [ -d "$PREFIX" ]; then
  cp -a "$WORK/payload$PREFIX/." "$PREFIX/"
fi

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/forge-cvt/MANIFEST" "$WORK/payload" \
  "$OUT/altitude-forge-cvt-1.0.0-amd64.altpkg"
