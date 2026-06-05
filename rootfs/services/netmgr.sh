#!/usr/bin/env bash
# Networking on the disk-root, minibash-native: NO NetworkManager (it stays
# stuck "unavailable" on this non-systemd box). We bring interfaces up ourselves
# and use busybox udhcpc for DHCP -- which is what actually works here. The udhcpc
# *script* is what applies the lease; without it the interface stays at
# 127.0.0.1 (the bug we chased for days). Config + live state live in the
# `network` bdb table.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export BDB_PATH="${BDB_PATH:-/var/bdb}"
exec >>/var/log/netmgr.log 2>&1

BDB=/bin/bdb
log() { echo "netmgr: $* ($(date 2>/dev/null))"; }

# WiFi creds live in a gitignored file so the PSK never lands in the public
# repo. Edit /etc/minibash/wifi.creds (WIFI_SSID=/WIFI_PSK=) on the box, or just
# `bdb update network --where ssid=... psk=...` once seeded.
DEF_SSID="Livebox-E130"
DEF_PSK=""
[ -f /etc/minibash/wifi.creds ] && . /etc/minibash/wifi.creds
DEF_SSID="${WIFI_SSID:-$DEF_SSID}"
DEF_PSK="${WIFI_PSK:-$DEF_PSK}"

# NetworkManager only got in the way here; make sure it is not fighting us.
[ -n "$(pidof NetworkManager 2>/dev/null)" ] && kill $(pidof NetworkManager) 2>/dev/null

# --- udhcpc lease-apply script (THE missing piece) -------------------------
DHS=/usr/share/udhcpc/default.script
mkdir -p /usr/share/udhcpc
cat > "$DHS" <<'EOF'
#!/bin/sh
case "$1" in
  deconfig) ifconfig "$interface" 0.0.0.0 ;;
  bound|renew)
    ifconfig "$interface" "$ip" netmask "${subnet:-255.255.255.0}"
    if [ -n "$router" ]; then route del default 2>/dev/null; route add default gw "$router"; fi
    : > /etc/resolv.conf
    for d in $dns; do echo "nameserver $d" >> /etc/resolv.conf; done
    ;;
esac
EOF
chmod +x "$DHS"
dhcp() { busybox udhcpc -i "$1" -s "$DHS" -t 8 -T 2 -n -q >/dev/null 2>&1; }
ip4()  { ip -4 addr show "$1" 2>/dev/null | awk '/inet /{print $2; exit}'; }

# --- bdb `network` table: config + live state ------------------------------
# Parse `bdb dump` (TAB-separated, machine-readable). `bdb select` prints a
# pretty ASCII table (| col |), which is NOT parsable. Seed with non-empty
# placeholders -- bdb rejects empty field values.
net_get() { # net_get <column> -> value from the first row
  $BDB dump network 2>/dev/null \
    | awk -F'\t' -v c="$1" 'NR==1{for(i=1;i<=NF;i++)if($i==c)k=i;next} {print $k; exit}'
}
$BDB tables 2>/dev/null | grep -qx network \
  || $BDB create network ssid:text:pk psk:text ifname:text managed:text state:text ip:text >/dev/null 2>&1 || true
if [ -z "$($BDB dump network 2>/dev/null | tail -n +2)" ]; then
  $BDB insert network ssid="$DEF_SSID" psk="$DEF_PSK" ifname="auto" \
    managed="direct" state="down" ip="0.0.0.0" >/dev/null 2>&1 || true
fi
SSID="$(net_get ssid)"; [ -n "$SSID" ] || SSID="$DEF_SSID"
PSK="$(net_get psk)";   [ -n "$PSK" ]  || PSK="$DEF_PSK"
net_state() { $BDB update network --where "ssid=$SSID" "$@" >/dev/null 2>&1 || true; }

# --- drivers (no udev cold-plug here) --------------------------------------
for m in cfg80211 mac80211 rfkill iwlwifi iwlmvm iwldvm \
  r8169 r8125 e1000e igb \
  rtw88_core rtw88_pci rtw89_core rtw89_pci rtl8xxxu \
  ath9k ath10k_pci ath11k_pci brcmfmac mt76 mt7921e; do
  modprobe "$m" 2>/dev/null || true
done
rfkill unblock all 2>/dev/null || true

# --- discover interfaces ---------------------------------------------------
ETH=""
for d in /sys/class/net/*; do
  n=$(basename "$d"); case "$n" in lo|wl*) continue;; esac
  [ -d "$d/device" ] && { ETH="$n"; break; }
done
WIF=""
for d in /sys/class/net/*; do [ -d "$d/wireless" ] && { WIF=$(basename "$d"); break; }; done
log "interfaces: eth=${ETH:-none} wifi=${WIF:-none} ssid=$SSID"

# --- main loop: ethernet first (no auth), then wifi ------------------------
while true; do
  if [ -n "$ETH" ]; then
    ip link set "$ETH" up 2>/dev/null
    if [ "$(cat /sys/class/net/$ETH/carrier 2>/dev/null)" = "1" ]; then
      [ -z "$(ip4 $ETH)" ] && { log "dhcp $ETH"; dhcp "$ETH"; }
      a="$(ip4 $ETH)"
      if [ -n "$a" ]; then
        net_state ifname="$ETH" state="connected" managed="eth" ip="$a"
        log "$ETH=$a"; sleep 30; continue
      fi
    fi
  fi

  if [ -n "$WIF" ]; then
    ip link set "$WIF" up 2>/dev/null
    if ! iw dev "$WIF" link 2>/dev/null | grep -q 'Connected'; then
      [ -n "$(pidof wpa_supplicant 2>/dev/null)" ] && kill $(pidof wpa_supplicant) 2>/dev/null
      sleep 1
      wpa_passphrase "$SSID" "$PSK" > /tmp/wpa.conf 2>/dev/null
      wpa_supplicant -B -i "$WIF" -c /tmp/wpa.conf >/dev/null 2>&1
      sleep 8
    fi
    if iw dev "$WIF" link 2>/dev/null | grep -q 'Connected'; then
      [ -z "$(ip4 $WIF)" ] && { log "dhcp $WIF"; dhcp "$WIF"; }
      a="$(ip4 $WIF)"
      if [ -n "$a" ]; then
        net_state ifname="$WIF" state="connected" managed="wifi" ip="$a"
        log "$WIF=$a"; sleep 30; continue
      fi
    fi
  fi

  net_state state="connecting"
  log "no link yet (eth carrier=$([ -n "$ETH" ] && cat /sys/class/net/$ETH/carrier 2>/dev/null || echo -))"
  sleep 10
done
