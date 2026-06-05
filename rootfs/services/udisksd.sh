#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

if pgrep -x udisksd >/dev/null 2>&1; then
  echo "udisksd: already running"
  exec sleep infinity
fi

for u in /usr/libexec/udisks2/udisksd /usr/lib/udisks2/udisksd; do
  if [ -x "$u" ]; then
    echo "udisksd: starting $u"
    exec "$u" --no-debug
  fi
done

echo "udisksd: binary missing"
exec sleep infinity
