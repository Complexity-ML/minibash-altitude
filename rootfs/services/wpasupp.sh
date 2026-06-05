#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
exec >>/var/log/wpa_supplicant-dbus.log 2>&1

mkdir -p /run/wpa_supplicant
if pgrep -x wpa_supplicant >/dev/null 2>&1; then
  echo "wpasupp: already running"
  exec sleep infinity
fi

echo "wpasupp: starting D-Bus supplicant"
exec wpa_supplicant -u -s -O /run/wpa_supplicant
