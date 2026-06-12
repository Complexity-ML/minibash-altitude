#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/workshop" "$TMP/repo/recipes/demo"

cat > "$TMP/repo/recipes/demo/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$ALTITUDE_RECIPE_WORK" = "$ALTITUDE_BUILD_ROOT/source-work/demo" ]
[ "$ALTITUDE_RECIPE_OUT" = "$ALTITUDE_PACKAGE_STAGING" ]
mkdir -p "$ALTITUDE_RECIPE_WORK" "$ALTITUDE_RECIPE_OUT"
echo demo > "$ALTITUDE_RECIPE_OUT/demo.altpkg"
EOF
chmod +x "$TMP/repo/recipes/demo/build.sh"

mkdir -p "$TMP/repo/scripts"
cp "$ROOT/scripts/build-source-recipe.sh" "$TMP/repo/scripts/build-source-recipe.sh"

(
  cd "$TMP/repo"
  source "$ROOT/scripts/use-altitude-workshop.sh"
  [ "$ALTITUDE_WORKSHOP_ROOT" = /srv/altitude ]
)

(
  cd "$TMP/repo"
  ALTITUDE_WORKSHOP_ROOT="$TMP/workshop" source "$ROOT/scripts/use-altitude-workshop.sh"
  [ "$ALTITUDE_SOURCE_CACHE" = "$TMP/workshop/sources" ]
  [ "$ALTITUDE_BUILD_ROOT" = "$TMP/workshop/builds" ]
  [ "$ALTITUDE_PACKAGE_STAGING" = "$TMP/workshop/packages-staging" ]
  [ "$ALTITUDE_REPO_ROOT" = "$TMP/workshop/repository" ]
  scripts/build-source-recipe.sh demo
  [ -f "$TMP/workshop/packages-staging/demo.altpkg" ]
)

mkdir -p "$TMP/workshop/packages-staging" "$TMP/workshop/repository"
cat > "$TMP/workshop/packages-staging/altitude-demo-1.0-all.altpkg" <<'EOF'
fake
EOF
cat > "$TMP/altrepo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  add)
    mkdir -p "$ALTITUDE_REPO_ROOT/packages"
    cp "$2" "$ALTITUDE_REPO_ROOT/packages/$(basename "$2")"
    ;;
  verify)
    [ -f "$ALTITUDE_REPO_ROOT/packages/altitude-demo-1.0-all.altpkg" ]
    ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$TMP/altrepo"

ALTITUDE_WORKSHOP_ROOT="$TMP/workshop" \
ALTITUDE_PACKAGE_STAGING="$TMP/workshop/packages-staging" \
ALTITUDE_REPO_ROOT="$TMP/workshop/repository" \
ALTITUDE_ALTREPO="$TMP/altrepo" \
  bash "$ROOT/scripts/publish-workshop-packages.sh" >/dev/null

[ -f "$TMP/workshop/repository/packages/altitude-demo-1.0-all.altpkg" ]

echo "Altitude workshop pipeline: ok"
