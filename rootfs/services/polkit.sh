#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

mkdir -p /run/polkit-1/rules.d /usr/local/share/polkit-1/rules.d \
  /etc/polkit-1/rules.d /usr/share/polkit-1/rules.d

if [ ! -S /run/dbus/system_bus_socket ]; then
  echo "polkit: waiting for dbus"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -S /run/dbus/system_bus_socket ] && break
    sleep 1
  done
fi

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
