#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/out/BOOTX64-omen-polish.EFI}"
GRUB_CFG="$(mktemp)"
FONT_ARG=()

cleanup() { rm -f "$GRUB_CFG"; }
trap cleanup EXIT

for font in /usr/share/grub/unicode.pf2 /usr/share/grub/ascii.pf2; do
  if [ -f "$font" ]; then
    FONT_ARG=("boot/grub/fonts/$(basename "$font")=$font")
    break
  fi
done

cat > "$GRUB_CFG" <<'CFG'
set timeout=2
set default=0
set gfxmode=1920x1080,auto
set gfxpayload=keep
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
terminal_input console serial
insmod all_video
insmod gfxterm
if loadfont /boot/grub/fonts/unicode.pf2; then
  terminal_output gfxterm console serial
else
  terminal_output console serial
fi
search --no-floppy --label MINIBASHEFI --set=root

menuentry "Altitude Linux OMEN (GNOME, quiet)" {
  search --no-floppy --label MINIBASHEFI --set=root
  linux /altitude-native/kernel root=LABEL=altitude-native rootfstype=ext4 rw fsck.repair=yes init=/init altitude.init=systemd systemd.unit=graphical.target iwlmvm.power_scheme=1 console=tty0 panic=0 quiet loglevel=3 vt.global_cursor_default=0 minibash.tty=tty1 minibash.autologin=root minibash.keymap=fr
}

menuentry "Altitude Linux OMEN (serial repair)" {
  search --no-floppy --label MINIBASHEFI --set=root
  linux /altitude-native/kernel root=LABEL=altitude-native rootfstype=ext4 rw fsck.repair=yes init=/init altitude.init=systemd systemd.unit=multi-user.target iwlmvm.power_scheme=1 console=ttyS0,115200 panic=0 loglevel=7 minibash.tty=ttyS0 minibash.autologin=root minibash.keymap=fr
}

menuentry "Altitude Linux OMEN (BusyBox fallback)" {
  search --no-floppy --label MINIBASHEFI --set=root
  linux /altitude-native/kernel root=LABEL=altitude-native rootfstype=ext4 rw fsck.repair=yes init=/init altitude.init=busybox iwlmvm.power_scheme=1 console=tty0 panic=0 loglevel=4 minibash.tty=tty1 minibash.autologin=root minibash.keymap=fr
}
CFG

mkdir -p "$(dirname "$OUT")"
grub-mkstandalone \
  -O x86_64-efi \
  --modules="part_gpt fat ext2 search search_label linux normal configfile efi_gop efi_uga all_video serial terminal font gfxterm" \
  -o "$OUT" \
  "boot/grub/grub.cfg=$GRUB_CFG" \
  "${FONT_ARG[@]}"

ls -lh "$OUT"
