#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="${ALTITUDE_SOURCES_LOCK:-$ROOT/sources/SOURCES.lock}"
CACHE="${ALTITUDE_SOURCE_CACHE:-$ROOT/out/source-cache}"

mkdir -p "$CACHE"

awk '
  BEGIN { RS=""; FS="\n" }
  {
    source = version = url = sha = ""
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^Source: /) source = substr($i, 9)
      if ($i ~ /^Version: /) version = substr($i, 10)
      if ($i ~ /^URL: /) url = substr($i, 6)
      if ($i ~ /^SHA256: /) sha = substr($i, 9)
    }
    if (source != "" && url != "" && sha != "")
      print source "\t" version "\t" url "\t" sha
  }
' "$LOCK" | while IFS="$(printf '\t')" read -r source version url sha; do
  file="$CACHE/${url##*/}"
  if [ -f "$file" ]; then
    got="$(sha256sum "$file" | awk '{print $1}')"
    if [ "$got" = "$sha" ]; then
      printf '[source-cache] ok %s %s\n' "$source" "$version"
      continue
    fi
    printf '[source-cache] bad checksum, refetch %s\n' "$source" >&2
    rm -f "$file"
  fi
  printf '[source-cache] fetch %s %s\n' "$source" "$version"
  rm -f "$file.part"
  curl -fL \
    --connect-timeout 20 \
    --speed-limit 1024 \
    --speed-time 30 \
    --retry 5 \
    --retry-delay 2 \
    --retry-all-errors \
    "$url" -o "$file.part"
  got="$(sha256sum "$file.part" | awk '{print $1}')"
  if [ "$got" != "$sha" ]; then
    echo "checksum mismatch for $source: got $got expected $sha" >&2
    rm -f "$file.part"
    exit 1
  fi
  mv "$file.part" "$file"
done
