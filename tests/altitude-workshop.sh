#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/dev" "$TMP/mnt" "$TMP/etc/altitude"
touch "$TMP/dev/sda4"

cat > "$TMP/bin/id" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = -u ] && { echo 0; exit 0; }
/usr/bin/id "$@"
EOF
cat > "$TMP/bin/blkid" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  -L) exit 0 ;;
  "$TMP/dev/sda4") echo "$TMP/dev/sda4: LABEL=\"altitude-spare\" TYPE=\"ext4\"" ;;
  *) exit 2 ;;
esac
EOF
cat > "$TMP/bin/mount" <<EOF
#!/usr/bin/env bash
mkdir -p "$TMP/mnt"
echo "$TMP/dev/sda4 $TMP/mnt ext4 rw,noatime 0 0" >> "$TMP/proc-mounts"
EOF
cat > "$TMP/bin/altrepo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  init) mkdir -p "$ALTITUDE_REPO_ROOT/packages" "$ALTITUDE_REPO_ROOT/private"; : > "$ALTITUDE_REPO_ROOT/INDEX" ;;
  keygen) mkdir -p "$ALTITUDE_REPO_ROOT/private"; echo private > "$ALTITUDE_REPO_ROOT/private/repository.pem"; echo public > "$ALTITUDE_REPO_ROOT/repository.pem" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$TMP/bin/"*
: > "$TMP/fstab"
: > "$TMP/proc-mounts"

PATH="$TMP/bin:$PATH" \
ALTITUDE_WORKSHOP_DEVICE="$TMP/dev/sda4" \
ALTITUDE_WORKSHOP_MOUNT="$TMP/mnt" \
ALTITUDE_FSTAB="$TMP/fstab" \
ALTITUDE_REPO_CONF="$TMP/etc/altitude/repositories.conf" \
  bash "$ROOT/scripts/init-altitude-workshop.sh"

grep -q "LABEL=altitude-spare $TMP/mnt ext4 defaults,noatime,nofail 0 2" "$TMP/fstab"
[ -d "$TMP/mnt/repository/packages" ]
[ -d "$TMP/mnt/sources" ]
[ -d "$TMP/mnt/builds" ]
[ -d "$TMP/mnt/logs" ]
[ -d "$TMP/mnt/images" ]
[ -f "$TMP/mnt/repository/repository.pem" ]
grep -q "Location: file://$TMP/mnt/repository" "$TMP/etc/altitude/repositories.conf"

echo "Altitude workshop init: ok"
