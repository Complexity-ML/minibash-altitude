#!/bin/busybox sh
# minibash disk-root boot stub. This runs as PID 1 inside the SMALL boot
# initramfs whose only job is: load storage + ext4 drivers, mount the real
# root filesystem given by root=, then switch_root into it and exec the real
# init (minit). The full rootfs (incl. GNOME) lives on disk, not in RAM.
set -- # noop, keep busybox happy

BB=/bin/busybox

$BB mkdir -p /proc /sys /dev /newroot
$BB mount -t proc proc /proc 2>/dev/null
$BB mount -t sysfs sysfs /sys 2>/dev/null
$BB mount -t devtmpfs devtmpfs /dev 2>/dev/null

log() { $BB echo "[boot] $*"; }

# Load storage controllers, disk + filesystem drivers. The boot initramfs ships
# a curated /lib/modules/<ver> with a depmod index so modprobe resolves deps.
log "loading storage/fs modules"
for m in libata libahci ahci ata_piix ata_generic sd_mod nvme \
         virtio_pci virtio_blk virtio_scsi \
         usb-storage uas \
         crc32c_generic crc32c-intel libcrc32c crc16 mbcache jbd2 ext4 \
         vfat nls_cp437 nls_ascii; do
  $BB modprobe "$m" 2>/dev/null
done
# settle: give the kernel a moment to probe disks
$BB sleep 2

# Parse root= and rootfstype= from the kernel command line.
root=""
rootfstype="ext4"
rootflags="rw"
for arg in $($BB cat /proc/cmdline); do
  case "$arg" in
    root=*)        root="${arg#root=}" ;;
    rootfstype=*)  rootfstype="${arg#rootfstype=}" ;;
    ro)            rootflags="ro" ;;
    rw)            rootflags="rw" ;;
  esac
done

# Resolve UUID=/LABEL= forms via the by-uuid/by-label symlinks (mdev/devtmpfs).
case "$root" in
  UUID=*)  root="$($BB findfs "$root" 2>/dev/null || $BB echo "/dev/disk/by-uuid/${root#UUID=}")" ;;
  LABEL=*) root="$($BB findfs "$root" 2>/dev/null || $BB echo "/dev/disk/by-label/${root#LABEL=}")" ;;
esac

log "root=$root type=$rootfstype ($rootflags)"

# Wait for the root device to appear (slow USB/SATA enumeration).
i=0
while [ ! -b "$root" ] && [ "$i" -lt 30 ]; do
  $BB sleep 1
  i=$((i + 1))
done

if [ ! -b "$root" ]; then
  log "FATAL: root device $root not found. Dropping to a shell."
  exec $BB sh
fi

$BB mkdir -p /newroot
if ! $BB mount -t "$rootfstype" -o "$rootflags" "$root" /newroot; then
  log "FATAL: cannot mount $root. Dropping to a shell."
  exec $BB sh
fi

# Hand over: move our pseudo-fs into the new root and switch_root to minit.
for fs in proc sys dev; do
  $BB mkdir -p "/newroot/$fs"
  $BB mount --move "/$fs" "/newroot/$fs" 2>/dev/null
done

if [ ! -x /newroot/init ] && [ ! -x /newroot/sbin/init ]; then
  log "FATAL: no /init on the new root. Dropping to a shell."
  exec $BB sh
fi

log "switch_root -> /init"
exec $BB switch_root /newroot /init
