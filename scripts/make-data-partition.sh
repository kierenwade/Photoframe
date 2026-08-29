#!/usr/bin/env bash
# Create the writable third partition (/data) on the SD card, filling the free
# space left after rootfs. Run ONCE, as root, BEFORE enabling Overlay FS.
#
# Prerequisite: the first-boot rootfs auto-expand must have been disabled
# (remove the `init=...firstboot` / `init_resize.sh` token from cmdline.txt
# before first boot) so there is unallocated space to use.
#
#   sudo /opt/frame-tv-sync/scripts/make-data-partition.sh [/dev/mmcblk0]
set -euo pipefail

DISK="${1:-/dev/mmcblk0}"
LABEL="frame-data"
MNT="/data"
APP_USER="frame"

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
[[ -b $DISK ]]     || { echo "no such disk: $DISK" >&2; exit 1; }

# partition node naming: /dev/mmcblk0 -> p3, /dev/sda -> 3
case "$DISK" in
  *[0-9]) PART="${DISK}p3" ;;
  *)      PART="${DISK}3"  ;;
esac

if [[ -b $PART ]]; then
  echo "$PART already exists — skipping partition creation"
else
  apt-get install -y --no-install-recommends parted >/dev/null 2>&1 || true

  disk_end=$(parted -ms "$DISK" unit s print | awk -F: 'NR==2 {gsub(/s/,"",$2); print $2}')
  p2_end=$(parted -ms "$DISK" unit s print   | awk -F: '/^2:/  {gsub(/s/,"",$3); print $3}')
  free=$(( disk_end - p2_end ))

  if (( free < 2 * 1024 * 1024 )); then   # < ~1 GiB
    echo "Only ${free}s free after rootfs." >&2
    echo "The auto-expand wasn't disabled. Re-flash and remove the" >&2
    echo "'init=/usr/lib/raspberrypi-sys-mods/firstboot' (or 'init_resize.sh')" >&2
    echo "token from bootfs/cmdline.txt before first boot." >&2
    exit 1
  fi

  start=$(( p2_end + 1 ))
  echo "creating $PART  (${start}s .. 100%)"
  parted -s "$DISK" unit s mkpart primary ext4 "${start}s" 100%
  partprobe "$DISK"; sleep 2
  mkfs.ext4 -L "$LABEL" -F "$PART"
fi

mkdir -p "$MNT"
if ! grep -q "LABEL=$LABEL" /etc/fstab; then
  echo "LABEL=$LABEL  $MNT  ext4  defaults,noatime,commit=30,errors=remount-ro  0  2" >> /etc/fstab
  echo "added /etc/fstab entry"
fi
mountpoint -q "$MNT" || mount "$MNT"

mkdir -p "$MNT"/{photos,secrets,logs}
id -u "$APP_USER" >/dev/null 2>&1 && chown -R "$APP_USER":"$APP_USER" "$MNT"
chmod 700 "$MNT/secrets"

echo
df -h "$MNT"
echo
echo "OK. Next: scripts/install.sh, add /data/secrets/*, test sync, then enable Overlay FS."
