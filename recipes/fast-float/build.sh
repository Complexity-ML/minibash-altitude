#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/fast-float}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
SYSROOT="$TOOLCHAIN/sysroot"
PAYLOAD="$WORK/payload"

rm -rf "$WORK"
mkdir -p "$PAYLOAD/usr/include/fast_float" "$PAYLOAD/usr/lib/pkgconfig" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"

cat > "$PAYLOAD/usr/include/fast_float/fast_float.h" <<'EOF'
#pragma once

#include <cerrno>
#include <charconv>
#include <cstdlib>
#include <cstring>
#include <string>
#include <system_error>

namespace fast_float {

using std::errc;

struct from_chars_result {
  const char* ptr;
  std::errc ec;
};

template <typename Float>
inline from_chars_result from_chars(const char* first, const char* last,
                                    Float& value, int base = 10) noexcept {
  std::string tmp(first, last);
  char* end = nullptr;
  errno = 0;
  double parsed = std::strtod(tmp.c_str(), &end);
  if (end == tmp.c_str())
    return {first, std::errc::invalid_argument};
  if (errno == ERANGE)
    return {first + (end - tmp.c_str()), std::errc::result_out_of_range};
  value = static_cast<Float>(parsed);
  return {first + (end - tmp.c_str()), std::errc{}};
}

} // namespace fast_float
EOF

cat > "$PAYLOAD/usr/lib/pkgconfig/fast_float.pc" <<'EOF'
prefix=/usr
includedir=${prefix}/include

Name: fast_float
Description: Minimal Altitude fast_float compatibility header
Version: 8.0.0
Cflags: -I${includedir}
EOF

install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: Altitude Linux"
  echo "Version: 8.0.0"
  echo "Build: header-only fast_float compatibility shim"
  echo "Upstream-note: replace with upstream fast_float for full parser coverage"
} > "$PAYLOAD/usr/share/altitude/sources/fast-float.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/fast-float/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-fast-float-8.0.0-all.altpkg"
