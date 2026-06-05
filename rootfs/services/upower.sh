#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

if pgrep -x upowerd >/dev/null 2>&1; then
  echo "upower: already running"
  exec sleep infinity
fi

for u in /usr/libexec/upowerd /usr/lib/upower/upowerd /usr/lib/upowerd; do
  if [ -x "$u" ]; then
    echo "upower: starting $u"
    exec "$u" --verbose
  fi
done

echo "upower: binary missing"
exec sleep infinity
