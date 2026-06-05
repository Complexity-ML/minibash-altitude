#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

mkdir -p /run/elogind /run/user

if pgrep -x elogind >/dev/null 2>&1; then
  echo "elogind: already running"
  exec sleep infinity
fi

for e in /lib/elogind/elogind /usr/lib/elogind/elogind /usr/libexec/elogind/elogind; do
  if [ -x "$e" ]; then
    echo "elogind: starting $e"
    exec "$e"
  fi
done

echo "elogind: binary missing"
exec sleep infinity
