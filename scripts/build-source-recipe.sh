#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?usage: build-source-recipe.sh NAME}"
RECIPE="$ROOT/recipes/$NAME/build.sh"
[ -x "$RECIPE" ] || {
  echo "source recipe missing or not executable: $RECIPE" >&2
  exit 1
}

if [ -n "${ALTITUDE_BUILD_ROOT:-}" ] && [ -z "${ALTITUDE_RECIPE_WORK:-}" ]; then
  export ALTITUDE_RECIPE_WORK="$ALTITUDE_BUILD_ROOT/source-work/$NAME"
fi
if [ -n "${ALTITUDE_PACKAGE_STAGING:-}" ] && [ -z "${ALTITUDE_RECIPE_OUT:-}" ]; then
  export ALTITUDE_RECIPE_OUT="$ALTITUDE_PACKAGE_STAGING"
fi

exec "$RECIPE"
