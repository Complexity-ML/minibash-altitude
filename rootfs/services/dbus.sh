#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

mkdir -p /run/dbus /var/lib/dbus
[ -s /etc/machine-id ] || dbus-uuidgen --ensure=/etc/machine-id 2>/dev/null || true
[ -s /var/lib/dbus/machine-id ] || cp /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true

if [ -S /run/dbus/system_bus_socket ]; then
  echo "dbus: system bus already running"
  exec sleep infinity
fi

echo "dbus: starting system bus"
exec dbus-daemon --system --nofork --nopidfile
