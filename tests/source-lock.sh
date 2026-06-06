#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT/sources/SOURCES.lock" "$TMP/SOURCES.lock"
printf fake > "$TMP/busybox-1.37.0.tar.bz2"
set +e
ALTITUDE_SOURCES_LOCK="$TMP/SOURCES.lock" \
ALTITUDE_SOURCE_CACHE="$TMP" \
  bash "$ROOT/scripts/source-fetch.sh" busybox >/dev/null 2>&1
status=$?
set -e
[ "$status" -ne 0 ]

set +e
ALTITUDE_SOURCES_LOCK="$TMP/SOURCES.lock" \
ALTITUDE_SOURCE_CACHE="$TMP" \
  bash "$ROOT/scripts/source-fetch.sh" unknown >/dev/null 2>&1
status=$?
set -e
[ "$status" -ne 0 ]

echo "Altitude source lock enforcement: ok"
