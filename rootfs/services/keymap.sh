#!/usr/bin/env bash
# keymap -- apply the console keyboard layout from the kernel cmdline
# (minibash.keymap=fr) using kbd's `loadkeys`.
#
# Why not the busybox loadkmap + /etc/keymaps/*.bmap path: kbd's `loadkeys -b`
# binary format is NOT the same as busybox loadkmap's format, so that path
# silently produced an empty keymap. `loadkeys <name>` sets the kernel keymap
# globally (all VTs), which is what we want.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

km=$(sed -n 's/.*minibash\.keymap=\([A-Za-z0-9_-]*\).*/\1/p' /proc/cmdline 2>/dev/null)
[ -n "$km" ] || km=$(/bin/bdb select registry \
  --where path=/system/locale/keymap 2>/dev/null | tail -n 1 | cut -f3)
[ -n "$km" ] || km=fr
# map short codes to real kbd keymap names
case "$km" in
  fr) km=fr-latin9 ;;
esac

command -v loadkeys >/dev/null 2>&1 || exit 0
# loadkeys sets the global kernel keymap; point it at the real console so it
# takes effect on tty1 even when run from a detached service.
loadkeys "$km" </dev/tty1 >/dev/null 2>&1 \
  || loadkeys "$km" </dev/console >/dev/null 2>&1 \
  || loadkeys "$km" >/dev/null 2>&1
