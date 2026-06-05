#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
exec >>/var/log/udevd.log 2>&1

log() { echo "udevd: $* ($(date 2>/dev/null))"; }

mkdir -p /run/udev /run/udev/data
for m in evdev mousedev usbhid hid_generic i2c_hid i2c_hid_acpi psmouse; do
  modprobe "$m" 2>/dev/null || true
done

if pgrep -x systemd-udevd >/dev/null 2>&1 || pgrep -x udevd >/dev/null 2>&1; then
  log "already running"
else
  log "starting"
  /lib/systemd/systemd-udevd --daemon 2>/dev/null || /usr/lib/systemd/systemd-udevd --daemon 2>/dev/null || true
fi

if command -v udevadm >/dev/null 2>&1; then
  udevadm trigger --action=add >/dev/null 2>&1 || true
  udevadm settle --timeout=10 >/dev/null 2>&1 || true
fi

exec sleep infinity
