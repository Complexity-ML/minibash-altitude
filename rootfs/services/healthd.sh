#!/usr/bin/env bash
# Periodic health auditor. It never restarts services; systemd owns lifecycle.
# This service only reports observed BDB/systemd audit facts for humans.
set -u

BDB_PATH="${BDB_PATH:-/var/bdb}"
export BDB_PATH

echo "healthd: auditor online"
while true; do
  if command -v systemctl >/dev/null 2>&1; then
    failed="$(systemctl list-units --failed --no-legend --no-pager 2>/dev/null |
      awk 'END { print NR + 0 }')"
    echo "healthd: systemd failed_units=${failed:-0}"
  fi
  if /bin/bdb tables 2>/dev/null | grep -qx systemd_audit; then
    /bin/bdb dump systemd_audit 2>/dev/null | tail -n +2 |
      awk -F '\t' '{ print "healthd: failed unit=" $1 " active=" $3 " sub=" $4 }'
  fi
  echo "healthd: audit complete"
  sleep 30
done
