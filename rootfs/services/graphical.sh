#!/usr/bin/env bash
# Bring up the GNOME desktop on the Debian disk-root WITHOUT systemd:
#   system D-Bus -> elogind (provides logind for mutter) -> lightdm display
#   manager (PAM opens a logind session via pam_elogind) -> GNOME session.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
exec >>/var/log/graphical.log 2>&1

log() { echo "graphical: $* ($(date 2>/dev/null))"; }
cleanup() {
  log "stopping lightdm session"
  killall gnome-session-failed gnome-session-binary gnome-shell lightdm Xorg 2>/dev/null || true
}
trap cleanup TERM INT

wait_bus_name() {
  local name="$1" i
  for i in 1 2 3 4 5; do
    busctl --system --no-pager list 2>/dev/null | awk '{print $1}' | grep -qx "$name" && return 0
    sleep 1
  done
  return 1
}

start_if_missing() {
  local name="$1" proc="$2"; shift 2
  if pgrep -x "$proc" >/dev/null 2>&1 && wait_bus_name "$name"; then
    return 0
  fi
  "$@" >/var/log/"$proc"-graphical.log 2>&1 &
  wait_bus_name "$name" || true
}

# GPU and input drivers (udev does not cold-plug them here)
for m in evdev mousedev usbhid hid_generic i2c_hid i2c_hid_acpi psmouse i915 amdgpu radeon nouveau virtio_gpu simpledrm; do
  modprobe "$m" 2>/dev/null || true
done

# Xorg/libinput normally discovers devices through udev. In minibash we do not
# run systemd, so start udevd directly when it exists and cold-plug once before
# LightDM starts. This is what creates /dev/input/event* early enough for X.
if command -v udevadm >/dev/null 2>&1; then
  mkdir -p /run/udev /run/udev/data
  if ! pgrep -x systemd-udevd >/dev/null 2>&1 && ! pgrep -x udevd >/dev/null 2>&1; then
    /lib/systemd/systemd-udevd --daemon 2>/var/log/udevd.log || true
  fi
  udevadm trigger --subsystem-match=input --action=add >/dev/null 2>&1 || true
  udevadm trigger --subsystem-match=drm --action=add >/dev/null 2>&1 || true
  udevadm settle --timeout=5 >/dev/null 2>&1 || true
fi

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
  mkdir -p /home/minibash/.config/autostart
  chown -R minibash:minibash /home/minibash
  chown minibash:minibash /run/user/1000
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
export GTK_A11Y=none
xset dpms force on 2>/dev/null || true
xset s off -dpms 2>/dev/null || true
xrandr --output eDP-1 --primary --auto --preferred --pos 0x0 --rotate normal 2>/dev/null || true
exec dbus-run-session -- sh -c '
  gsettings set org.gnome.desktop.session idle-delay 0 >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.screensaver lock-enabled false >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.background picture-options none >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.background primary-color "#101418" >/dev/null 2>&1 || true
  gsettings set org.gnome.shell favorite-apps "['\''org.gnome.Nautilus.desktop'\'', '\''minibash-services.desktop'\'']" >/dev/null 2>&1 || true
  exec gnome-session
'
EOF
  cp /etc/xdg/autostart/minibash-services.desktop /home/minibash/.config/autostart/minibash-services.desktop 2>/dev/null || true
  rm -f /home/minibash/.config/monitors.xml
  chown -R minibash:minibash /home/minibash/.config/autostart
  chown minibash:minibash /home/minibash/.xsessionrc /home/minibash/.xsession
  chmod +x /home/minibash/.xsession
fi

# 1. system D-Bus. Prefer the dbus BDB service when it is enabled, but keep a
# fallback here so graphical can still be launched manually.
[ -S /run/dbus/system_bus_socket ] || { log "starting dbus fallback"; dbus-daemon --system --fork --nopidfile; }
sleep 1

# 2. elogind (the logind implementation mutter talks to). Same idea: normally
# owned by the elogind BDB service, fallback for manual graphical starts.
log "checking desktop system services"
start_if_missing org.freedesktop.login1 elogind /usr/libexec/elogind
start_if_missing org.freedesktop.UPower upowerd /usr/libexec/upowerd --verbose
start_if_missing org.freedesktop.Accounts accounts-daemon /usr/libexec/accounts-daemon
start_if_missing org.freedesktop.UDisks2 udisksd /usr/libexec/udisks2/udisksd --no-debug
start_if_missing org.freedesktop.PolicyKit1 polkitd /usr/lib/polkit-1/polkitd --no-debug
mkdir -p /run/wpa_supplicant
if [ -x /usr/libexec/iwd ]; then
  start_if_missing net.connman.iwd iwd /usr/libexec/iwd
else
  start_if_missing fi.w1.wpa_supplicant1 wpa_supplicant /usr/sbin/wpa_supplicant -u -s -O /run/wpa_supplicant
fi
sleep 1

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
