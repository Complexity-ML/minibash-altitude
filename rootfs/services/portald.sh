#!/usr/bin/env bash
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
mkdir -p "$XDG_RUNTIME_DIR"
chown minibash:minibash "$XDG_RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

if pgrep -f xdg-desktop-portal >/dev/null 2>&1; then
  echo "portald: already running"
  exec sleep infinity
fi

echo "portald: starting xdg desktop portals"
su -s /bin/sh minibash -c 'XDG_RUNTIME_DIR=/run/user/1000 /usr/libexec/xdg-desktop-portal-gtk >/var/log/portal-gtk.log 2>&1 &' 2>/dev/null || true
exec su -s /bin/sh minibash -c 'XDG_RUNTIME_DIR=/run/user/1000 exec /usr/libexec/xdg-desktop-portal'
