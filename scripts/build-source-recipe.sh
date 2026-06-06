#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?usage: build-source-recipe.sh NAME}"
RECIPE="$ROOT/recipes/$NAME/build.sh"
[ -x "$RECIPE" ] || {
  echo "source recipe missing or not executable: $RECIPE" >&2
  exit 1
}
exec "$RECIPE"
