#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

if pgrep -x accounts-daemon >/dev/null 2>&1; then
  echo "accounts: already running"
  exec sleep infinity
fi

for a in /usr/libexec/accounts-daemon /usr/lib/accountsservice/accounts-daemon; do
  if [ -x "$a" ]; then
    echo "accounts: starting $a"
    "$a" &
    sleep 2
    while pgrep -x accounts-daemon >/dev/null 2>&1; do
      sleep 60
    done
    echo "accounts: daemon exited"
    exit 1
  fi
done

echo "accounts: binary missing"
exec sleep infinity
