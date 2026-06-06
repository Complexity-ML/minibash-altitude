#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="${ALTITUDE_SOURCES_LOCK:-$ROOT/sources/SOURCES.lock}"
CACHE="${ALTITUDE_SOURCE_CACHE:-$ROOT/out/source-cache}"
NAME="${1:?usage: source-fetch.sh NAME}"

die() { echo "source-fetch: $*" >&2; exit 1; }
stanza="$(
  awk -v wanted="$NAME" '
    BEGIN { RS=""; FS="\n" }
    {
      name=""
      for (i=1; i<=NF; i++)
        if ($i ~ /^Source: /) name=substr($i,9)
      if (name == wanted) print $0
    }
  ' "$LOCK"
)"
[ -n "$stanza" ] || die "source not locked: $NAME"
url="$(printf '%s\n' "$stanza" | sed -n 's/^URL: *//p')"
expected="$(printf '%s\n' "$stanza" | sed -n 's/^SHA256: *//p')"
file="$CACHE/${url##*/}"
mkdir -p "$CACHE"

if [ ! -f "$file" ]; then
  if command -v curl >/dev/null 2>&1; then
    curl -fL "$url" -o "$file.part"
  elif command -v wget >/dev/null 2>&1; then
    wget "$url" -O "$file.part"
  elif command -v busybox >/dev/null 2>&1; then
    busybox wget "$url" -O "$file.part"
  else
    die "curl, wget or BusyBox wget is required"
  fi
  mv "$file.part" "$file"
fi

got="$(sha256sum "$file" | awk '{print $1}')"
[ "$got" = "$expected" ] || die "checksum mismatch for ${url##*/}"
printf '%s\n' "$file"
