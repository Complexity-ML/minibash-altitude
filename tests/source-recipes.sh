#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for recipe in busybox binutils gcc-bootstrap linux-headers glibc-bootstrap forge-tools; do
  manifest="$ROOT/recipes/$recipe/MANIFEST"
  build="$ROOT/recipes/$recipe/build.sh"
  [ -f "$manifest" ]
  [ -x "$build" ]
  grep -q '^Format: altitude-package-1$' "$manifest"
  source_name="$recipe"
  [ "$recipe" != gcc-bootstrap ] || source_name=gcc
  [ "$recipe" != linux-headers ] || source_name=linux
  [ "$recipe" != glibc-bootstrap ] || source_name=glibc
  [ "$recipe" != forge-tools ] || source_name=m4
  grep -q "^Source: $source_name$" "$ROOT/sources/SOURCES.lock"
  bash -n "$build"
done

grep -q -- '--prefix="$PREFIX"' "$ROOT/recipes/binutils/build.sh"
grep -q '^PREFIX="/opt/altitude/toolchain"$' "$ROOT/recipes/binutils/build.sh"
grep -q -- '--with-pkgversion="Altitude Linux 0.1 bootstrap"' \
  "$ROOT/recipes/gcc-bootstrap/build.sh"
grep -q 'headers_install' "$ROOT/recipes/linux-headers/build.sh"
grep -q 'all-target-libgcc' "$ROOT/recipes/gcc-bootstrap/build.sh"
grep -q 'export PATH=.*toolchain_path/bin' \
  "$ROOT/recipes/gcc-bootstrap/build.sh"
grep -q -- '--host="$TARGET_TRIPLET"' \
  "$ROOT/recipes/glibc-bootstrap/build.sh"
grep -q 'libc_cv_slibdir=/usr/lib' \
  "$ROOT/recipes/glibc-bootstrap/build.sh"
grep -q 'forge_path/bin' "$ROOT/recipes/glibc-bootstrap/build.sh"
grep -q 'CXX=false' "$ROOT/recipes/glibc-bootstrap/build.sh"
grep -q "CXX = false.*CXX =" "$ROOT/recipes/glibc-bootstrap/build.sh"
grep -q -- '-fno-asynchronous-unwind-tables' \
  "$ROOT/recipes/glibc-bootstrap/patches/0001-x86_64-bootstrap-libc-sigaction.patch"
grep -q '^Source: bison$' "$ROOT/sources/SOURCES.lock"
grep -q '^Source: gawk$' "$ROOT/sources/SOURCES.lock"

echo "Altitude source recipes: ok"
