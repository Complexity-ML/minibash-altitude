#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSHOP="${ALTITUDE_WORKSHOP_ROOT:-/srv/altitude}"
STAGING="${ALTITUDE_PACKAGE_STAGING:-$WORKSHOP/packages-staging}"
REPO="${ALTITUDE_REPO_ROOT:-$WORKSHOP/repository}"
ALTREPO="${ALTITUDE_ALTREPO:-}"

die() { echo "publish-workshop-packages: $*" >&2; exit 1; }

if [ -z "$ALTREPO" ]; then
  if command -v altrepo >/dev/null 2>&1; then
    ALTREPO=altrepo
  elif [ -x /bin/altrepo ]; then
    ALTREPO=/bin/altrepo
  else
    ALTREPO="$ROOT/rootfs/bin/altrepo"
  fi
fi

[ -d "$STAGING" ] || die "staging directory missing: $STAGING"
mkdir -p "$REPO/packages"

published=0
for package in "$STAGING"/*.altpkg; do
  [ -f "$package" ] || continue
  case "$(basename "$package")" in ._*) continue ;; esac
  ALTITUDE_REPO_ROOT="$REPO" "$ALTREPO" add "$package"
  published=$((published + 1))
done

[ "$published" -gt 0 ] || die "no .altpkg files found in $STAGING"

ALTITUDE_REPO_ROOT="$REPO" "$ALTREPO" verify
if command -v pkg >/dev/null 2>&1; then
  pkg refresh
elif [ -x /bin/pkg ]; then
  /bin/pkg refresh
fi

echo "publish-workshop-packages: published $published package(s) to $REPO"
