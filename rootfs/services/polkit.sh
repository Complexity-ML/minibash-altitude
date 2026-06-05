#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

[ -S /run/dbus/system_bus_socket ] || { echo "polkit: waiting for dbus"; sleep 2; }

if pgrep -x polkitd >/dev/null 2>&1; then
  echo "polkit: already running"
  exec sleep infinity
fi

for p in /usr/lib/polkit-1/polkitd /usr/libexec/polkitd /usr/lib/polkit-1/polkit-agent-helper-1; do
  case "$p" in
    *polkitd) [ -x "$p" ] && { echo "polkit: starting $p"; exec "$p" --no-debug; } ;;
  esac
done

echo "polkit: polkitd missing"
exec sleep infinity
