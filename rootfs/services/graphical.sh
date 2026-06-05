#!/usr/bin/env bash
# Bring up the GNOME desktop on the Debian disk-root WITHOUT systemd:
#   system D-Bus -> elogind (provides logind for mutter) -> lightdm display
#   manager (PAM opens a logind session via pam_elogind) -> GNOME session.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
exec >>/var/log/graphical.log 2>&1

log() { echo "graphical: $* ($(date 2>/dev/null))"; }

# GPU drivers (udev does not cold-plug them here)
for m in i915 amdgpu radeon nouveau virtio_gpu simpledrm; do modprobe "$m" 2>/dev/null || true; done

# machine-id (logind/dbus need it)
if [ ! -s /etc/machine-id ]; then
  dbus-uuidgen --ensure=/etc/machine-id 2>/dev/null || tr -d '-' < /proc/sys/kernel/random/uuid > /etc/machine-id
fi
mkdir -p /run/dbus /run/elogind /run/lightdm /var/lib/lightdm /var/lib/lightdm-data /run/user
[ -s /var/lib/dbus/machine-id ] || { mkdir -p /var/lib/dbus; cp /etc/machine-id /var/lib/dbus/machine-id; }

# 1. system D-Bus
[ -S /run/dbus/system_bus_socket ] || { log "starting dbus"; dbus-daemon --system --fork; }
sleep 1

# 2. elogind (the logind implementation mutter talks to)
if ! pgrep -x elogind >/dev/null 2>&1; then
  log "starting elogind"
  for e in /lib/elogind/elogind /usr/lib/elogind/elogind /usr/libexec/elogind/elogind; do
    [ -x "$e" ] && { "$e" --daemon 2>/dev/null || "$e" & break; }
  done
fi
sleep 2

# 3. lightdm -> autologin -> GNOME
log "starting lightdm"
exec lightdm
