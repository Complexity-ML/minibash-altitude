#!/usr/bin/env bash
# Source this file to route Altitude builds through the workshop volume.
#
#   source scripts/use-altitude-workshop.sh
#   scripts/build-source-recipe.sh zlib
#   scripts/publish-workshop-packages.sh
#
# If executed directly, it prints shell exports that can be eval'd.

set -euo pipefail

ALTITUDE_WORKSHOP_ROOT="${ALTITUDE_WORKSHOP_ROOT:-/srv/altitude}"
ALTITUDE_SOURCE_CACHE="${ALTITUDE_SOURCE_CACHE:-$ALTITUDE_WORKSHOP_ROOT/sources}"
ALTITUDE_BUILD_ROOT="${ALTITUDE_BUILD_ROOT:-$ALTITUDE_WORKSHOP_ROOT/builds}"
ALTITUDE_PACKAGE_STAGING="${ALTITUDE_PACKAGE_STAGING:-$ALTITUDE_WORKSHOP_ROOT/packages-staging}"
ALTITUDE_RECIPE_OUT="${ALTITUDE_RECIPE_OUT:-$ALTITUDE_PACKAGE_STAGING}"
ALTITUDE_REPO_ROOT="${ALTITUDE_REPO_ROOT:-$ALTITUDE_WORKSHOP_ROOT/repository}"
ALTITUDE_LOG_ROOT="${ALTITUDE_LOG_ROOT:-$ALTITUDE_WORKSHOP_ROOT/logs}"

export ALTITUDE_WORKSHOP_ROOT
export ALTITUDE_SOURCE_CACHE
export ALTITUDE_BUILD_ROOT
export ALTITUDE_PACKAGE_STAGING
export ALTITUDE_RECIPE_OUT
export ALTITUDE_REPO_ROOT
export ALTITUDE_LOG_ROOT

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf 'export ALTITUDE_WORKSHOP_ROOT=%q\n' "$ALTITUDE_WORKSHOP_ROOT"
  printf 'export ALTITUDE_SOURCE_CACHE=%q\n' "$ALTITUDE_SOURCE_CACHE"
  printf 'export ALTITUDE_BUILD_ROOT=%q\n' "$ALTITUDE_BUILD_ROOT"
  printf 'export ALTITUDE_PACKAGE_STAGING=%q\n' "$ALTITUDE_PACKAGE_STAGING"
  printf 'export ALTITUDE_RECIPE_OUT=%q\n' "$ALTITUDE_RECIPE_OUT"
  printf 'export ALTITUDE_REPO_ROOT=%q\n' "$ALTITUDE_REPO_ROOT"
  printf 'export ALTITUDE_LOG_ROOT=%q\n' "$ALTITUDE_LOG_ROOT"
else
  mkdir -p "$ALTITUDE_SOURCE_CACHE" "$ALTITUDE_BUILD_ROOT" \
    "$ALTITUDE_PACKAGE_STAGING" "$ALTITUDE_REPO_ROOT" "$ALTITUDE_LOG_ROOT" \
    2>/dev/null || true
fi
