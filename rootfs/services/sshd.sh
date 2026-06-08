#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

PORT="${SSHD_PORT:-22}"
LOG="${SSHD_LOG:-/var/log/sshd.log}"
mkdir -p /etc/dropbear /var/log /run
exec >>"$LOG" 2>&1

log() { echo "sshd: $* ($(date 2>/dev/null || true))"; }

if ! command -v dropbear >/dev/null 2>&1; then
  log "dropbear binary missing; install dropbear-bin in builder"
  exec sleep 3600
fi

if [ ! -s /etc/dropbear/dropbear_ed25519_host_key ]; then
  if command -v dropbearkey >/dev/null 2>&1; then
    log "generating ed25519 host key"
    dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1 || true
  fi
fi

while true; do
  if pgrep -x dropbear >/dev/null 2>&1; then
    log "dropbear already running"
    exec sleep infinity
  fi
  log "dropbear listening on 0.0.0.0:${PORT}"
  dropbear -F -E -p "0.0.0.0:${PORT}"
  rc=$?
  log "dropbear exited rc=$rc; retrying in 3s"
  sleep 3
done
