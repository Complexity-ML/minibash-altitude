#!/usr/bin/env bash
set -euo pipefail

LABEL="${ALTITUDE_WORKSHOP_LABEL:-altitude-spare}"
MOUNTPOINT="${ALTITUDE_WORKSHOP_MOUNT:-/srv/altitude}"
REPO="$MOUNTPOINT/repository"
FSTAB="${ALTITUDE_FSTAB:-/etc/fstab}"
REPO_CONF="${ALTITUDE_REPO_CONF:-/etc/altitude/repositories.conf}"

die() { echo "init-altitude-workshop: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root"
command -v blkid >/dev/null 2>&1 || die "blkid is required"

device="${ALTITUDE_WORKSHOP_DEVICE:-}"
if [ -z "$device" ]; then
  device="$(blkid -L "$LABEL" 2>/dev/null || true)"
fi
if [ -z "$device" ]; then
  for candidate in /dev/sd*[0-9] /dev/nvme*n*p* /dev/vd*[0-9]; do
    [ -b "$candidate" ] || continue
    if blkid "$candidate" 2>/dev/null | grep -q "LABEL=\"$LABEL\""; then
      device="$candidate"
      break
    fi
  done
fi
[ -n "$device" ] || die "no filesystem with LABEL=$LABEL"

mkdir -p "$MOUNTPOINT"
if ! awk -v mp="$MOUNTPOINT" '$2 == mp { found=1 } END { exit !found }' \
    /proc/mounts 2>/dev/null; then
  if ! grep -q "[[:space:]]$MOUNTPOINT[[:space:]]" "$FSTAB" 2>/dev/null; then
    printf 'LABEL=%s %s ext4 defaults,noatime,nofail 0 2\n' \
      "$LABEL" "$MOUNTPOINT" >> "$FSTAB"
  fi
  mount "$MOUNTPOINT" || mount -t ext4 "$device" "$MOUNTPOINT"
fi

mkdir -p "$REPO/packages" "$MOUNTPOINT"/{sources,builds,logs,images,tmp}
chmod 1777 "$MOUNTPOINT/tmp"

if command -v altrepo >/dev/null 2>&1; then
  ALTITUDE_REPO_ROOT="$REPO" altrepo init
  if [ ! -f "$REPO/private/repository.pem" ]; then
    ALTITUDE_REPO_ROOT="$REPO" altrepo keygen
  fi
elif [ -x /bin/altrepo ]; then
  ALTITUDE_REPO_ROOT="$REPO" /bin/altrepo init
  if [ ! -f "$REPO/private/repository.pem" ]; then
    ALTITUDE_REPO_ROOT="$REPO" /bin/altrepo keygen
  fi
else
  die "altrepo is required"
fi

mkdir -p "$(dirname "$REPO_CONF")"
cat > "$REPO_CONF" <<EOF
Repository: local
Location: file://$REPO
Public-Key: $REPO/repository.pem
EOF

echo "init-altitude-workshop: mounted $device at $MOUNTPOINT"
echo "init-altitude-workshop: repository file://$REPO"
