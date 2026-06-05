#!/usr/bin/env bash
# Networking on the disk-root, minibash-native (NO NetworkManager -- it stays
# "unavailable" without systemd/udev). We bring interfaces up ourselves and use
# busybox udhcpc for DHCP. The udhcpc *script* is what applies the lease;
# without it the iface stays at 127.0.0.1 (the bug chased for days).
#
# Ethernet first (no auth). The onboard r8169 link flaps here, so DHCP is
# unreliable -> after a few failed DHCP rounds we fall back to a STATIC ip so
# the box is ALWAYS reachable after a reboot. Config + live state in the bdb
# `network` table; wired static defaults overridable via /etc/minibash/wifi.creds.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export BDB_PATH="${BDB_PATH:-/var/bdb}"
exec >>/var/log/netmgr.log 2>&1
BDB=/bin/bdb
log(){ echo "netmgr: $* ($(date 2>/dev/null))"; }

DEF_SSID="Livebox-E130"; DEF_PSK=""
# Wired static fallback (private LAN addr, not secret). Used ONLY if DHCP keeps
# failing, so the box is reachable even when the link flaps.
WIRED_IP="192.168.1.25/24"; WIRED_GW="192.168.1.1"; WIRED_DNS="192.168.1.1"
[ -f /etc/minibash/wifi.creds ] && . /etc/minibash/wifi.creds
DEF_SSID="${WIFI_SSID:-$DEF_SSID}"; DEF_PSK="${WIFI_PSK:-$DEF_PSK}"

DHS=/usr/share/udhcpc/default.script
mkdir -p /usr/share/udhcpc
cat > "$DHS" <<'EOF'
#!/bin/sh
case "$1" in
  bound|renew)
    ifconfig "$interface" "$ip" netmask "${subnet:-255.255.255.0}"
    [ -n "$router" ] && { route del default 2>/dev/null; route add default gw "$router"; }
    : > /etc/resolv.conf; for d in $dns; do echo "nameserver $d" >> /etc/resolv.conf; done ;;
esac
EOF
chmod +x "$DHS"
dhcp(){ busybox udhcpc -i "$1" -s "$DHS" -t 6 -T 2 -n -q >/dev/null 2>&1; }
ip4(){ ip -4 addr show "$1" 2>/dev/null | awk '/inet /{print $2; exit}'; }
carrier(){ cat "/sys/class/net/$1/carrier" 2>/dev/null; }

# bdb `network` table (parse `bdb dump`, TAB-separated; `bdb select` is ASCII art)
net_get(){ $BDB dump network 2>/dev/null | awk -F'\t' -v c="$1" 'NR==1{for(i=1;i<=NF;i++)if($i==c)k=i;next}{print $k;exit}'; }
$BDB tables 2>/dev/null | grep -qx network \
  || $BDB create network ssid:text:pk psk:text ifname:text managed:text state:text ip:text >/dev/null 2>&1 || true
if [ -z "$($BDB dump network 2>/dev/null | tail -n +2)" ]; then
  $BDB insert network ssid="$DEF_SSID" psk="${DEF_PSK:-none}" ifname="auto" managed="direct" state="down" ip="0.0.0.0" >/dev/null 2>&1 || true
fi
SSID="$(net_get ssid)"; [ -n "$SSID" ] || SSID="$DEF_SSID"
PSK="$(net_get psk)"; [ -n "$PSK" ] && [ "$PSK" != none ] || PSK="$DEF_PSK"
net_state(){ $BDB update network --where "ssid=$SSID" "$@" >/dev/null 2>&1 || true; }

for m in cfg80211 mac80211 rfkill iwlwifi iwlmvm r8169 r8125 e1000e igb; do modprobe "$m" 2>/dev/null || true; done
rfkill unblock all 2>/dev/null || true

detect_eth(){ local d n; for d in /sys/class/net/*; do n=${d##*/}; case "$n" in lo|wl*) continue;; esac; [ -e "$d/device" ] && { echo "$n"; return; }; done; }
detect_wifi(){ local d; for d in /sys/class/net/*; do [ -d "$d/wireless" ] && { echo "${d##*/}"; return; }; done; }

set_static(){ # set_static <iface>
  ip addr add "$WIRED_IP" dev "$1" 2>/dev/null
  [ -n "$WIRED_GW" ] && { ip route del default 2>/dev/null; ip route add default via "$WIRED_GW" 2>/dev/null; }
  [ -n "$WIRED_DNS" ] && echo "nameserver $WIRED_DNS" > /etc/resolv.conf
}

while true; do
  ETH="$(detect_eth)"; WIF="$(detect_wifi)"

  # 1) ethernet (no auth). The r8169 link FLAPS, so DHCP is unreliable and
  #    carrier is often 0 -> do NOT gate on carrier. Best-effort DHCP, then set
  #    the STATIC ip UNCONDITIONALLY so an IP is guaranteed at every boot (it's
  #    valid the moment the link comes up).
  if [ -n "$ETH" ]; then
    ip link set "$ETH" up 2>/dev/null
    if [ -z "$(ip4 $ETH)" ]; then
      [ "$(carrier $ETH)" = "1" ] && { log "dhcp $ETH"; dhcp "$ETH"; }
      if [ -z "$(ip4 $ETH)" ] && [ -n "$WIRED_IP" ]; then
        log "static $WIRED_IP on $ETH"; set_static "$ETH"
      fi
    fi
    if [ -n "$(ip4 $ETH)" ]; then
      net_state ifname="$ETH" state="connected" managed="eth" ip="$(ip4 $ETH)"
      log "$ETH=$(ip4 $ETH)"; sleep 30; continue
    fi
  fi

  # 2) wifi fallback (only if no ethernet IP and a PSK is known)
  if [ -n "$WIF" ] && [ -n "$PSK" ]; then
    ip link set "$WIF" up 2>/dev/null
    if ! iw dev "$WIF" link 2>/dev/null | grep -q Connected; then
      [ -n "$(pidof wpa_supplicant 2>/dev/null)" ] && kill $(pidof wpa_supplicant) 2>/dev/null
      sleep 1
      wpa_passphrase "$SSID" "$PSK" > /tmp/wpa.conf 2>/dev/null
      wpa_supplicant -B -i "$WIF" -c /tmp/wpa.conf >/dev/null 2>&1; sleep 8
    fi
    if iw dev "$WIF" link 2>/dev/null | grep -q Connected; then
      [ -z "$(ip4 $WIF)" ] && dhcp "$WIF"
      if [ -n "$(ip4 $WIF)" ]; then
        net_state ifname="$WIF" state="connected" managed="wifi" ip="$(ip4 $WIF)"
        log "$WIF=$(ip4 $WIF)"; sleep 30; continue
      fi
    fi
  fi

  net_state state="connecting"
  log "no link yet (eth=${ETH:-none} carrier=$([ -n "$ETH" ] && carrier "$ETH" || echo -))"
  sleep 8
done
