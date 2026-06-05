#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/var/run/lightdm/root/:0}"

apply_display() {
  command -v xrandr >/dev/null 2>&1 || return 0
  xset dpms force on >/tmp/displayd-xset.log 2>&1 || true
  xset s off -dpms >>/tmp/displayd-xset.log 2>&1 || true
  xrandr --query >/tmp/displayd-xrandr.log 2>&1 || return 0

  primary="$(awk '/ connected/{print $1; exit}' /tmp/displayd-xrandr.log)"
  [ -n "$primary" ] || return 0

  xrandr --output "$primary" --primary --auto --preferred --pos 0x0 --rotate normal >/tmp/displayd-apply.log 2>&1 || true

  awk '/ connected/{print $1}' /tmp/displayd-xrandr.log | while read -r out; do
    [ "$out" = "$primary" ] && continue
    xrandr --output "$out" --off >/dev/null 2>&1 || true
  done
}

echo "displayd: managing primary display"
for _ in 1 2 3 4 5; do
  apply_display
  sleep 2
done
while true; do
  apply_display
  sleep 20
done
