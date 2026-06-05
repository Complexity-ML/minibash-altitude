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

# LightDM autologin runs as the desktop user. Keep its home/runtime dirs sane:
# bad ownership here makes GNOME exit immediately with status 13.
if id minibash >/dev/null 2>&1; then
  mkdir -p /home/minibash/.config /home/minibash/.local/share /run/user/1000 /tmp/.ICE-unix /tmp/.X11-unix
  chown -R minibash:minibash /home/minibash /run/user/1000
  chmod 755 /home/minibash
  chmod 700 /run/user/1000
  chmod 1777 /tmp/.ICE-unix /tmp/.X11-unix
  cat > /home/minibash/.xsessionrc <<'EOF'
export XDG_RUNTIME_DIR=/run/user/1000
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export LIBGL_ALWAYS_SOFTWARE=1
EOF
  cat > /home/minibash/.xsession <<'EOF'
#!/bin/sh
export XDG_RUNTIME_DIR=/run/user/1000
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export LIBGL_ALWAYS_SOFTWARE=1
xrandr --output eDP-1 --primary --mode 1920x1080 --rate 60 --pos 0x0 --rotate normal 2>/dev/null || true
exec dbus-run-session -- gnome-session
EOF
  cat > /home/minibash/.config/monitors.xml <<'EOF'
<monitors version="2">
  <configuration>
    <logicalmonitor>
      <x>0</x>
      <y>0</y>
      <scale>1</scale>
      <primary>yes</primary>
      <monitor>
        <monitorspec>
          <connector>eDP-1</connector>
          <vendor>unknown</vendor>
          <product>unknown</product>
          <serial>unknown</serial>
        </monitorspec>
        <mode>
          <width>1920</width>
          <height>1080</height>
          <rate>60.000</rate>
        </mode>
      </monitor>
    </logicalmonitor>
  </configuration>
</monitors>
EOF
  chown minibash:minibash /home/minibash/.xsessionrc /home/minibash/.xsession /home/minibash/.config/monitors.xml
  chmod +x /home/minibash/.xsession
fi

# 1. system D-Bus. Prefer the dbus BDB service when it is enabled, but keep a
# fallback here so graphical can still be launched manually.
[ -S /run/dbus/system_bus_socket ] || { log "starting dbus fallback"; dbus-daemon --system --fork; }
sleep 1

# 2. elogind (the logind implementation mutter talks to). Same idea: normally
# owned by the elogind BDB service, fallback for manual graphical starts.
if ! pgrep -x elogind >/dev/null 2>&1; then
  log "starting elogind fallback"
  for e in /lib/elogind/elogind /usr/lib/elogind/elogind /usr/libexec/elogind/elogind; do
    [ -x "$e" ] && { "$e" & break; }
  done
fi
sleep 2

# 3. lightdm -> autologin -> GNOME
if pgrep -x lightdm >/dev/null 2>&1; then
  log "lightdm already running"
  exec sleep infinity
fi

log "starting lightdm"
lightdm &
sleep 3
while pgrep -x lightdm >/dev/null 2>&1; do
  sleep 60
done
log "lightdm exited"
exit 1
