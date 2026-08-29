#!/usr/bin/env bash
# Enable a read-only root (Overlay FS) while keeping /data writable.
#
# raspi-config's Overlay FS uses `overlayroot=tmpfs`, whose default recurse=1
# also freezes the frame-data partition (writes to /data would be RAM-only and
# lost on reboot). We force recurse=0 so only / is read-only.
#
#   sudo /opt/frame-tv-sync/scripts/enable-overlay.sh
#   sudo reboot
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
CMDLINE=/boot/firmware/cmdline.txt

if ! grep -q 'overlayroot=' "$CMDLINE"; then
  echo "== enabling Overlay FS via raspi-config =="
  raspi-config nonint do_overlayfs 0 || {
    echo "!! nonint call failed — enable it in 'sudo raspi-config' → Performance →" >&2
    echo "!! Overlay File System, do NOT reboot, then run this script again." >&2
    exit 1
  }
fi

mount -o remount,rw /boot/firmware
grep -q 'recurse=0' "$CMDLINE" ||
  sed -i 's/overlayroot=tmpfs/overlayroot=tmpfs:recurse=0/' "$CMDLINE"
mount -o remount,ro /boot/firmware || true

echo
echo "cmdline: $(grep -o 'overlayroot=[^ ]*' "$CMDLINE" || echo '(not set!)')"
echo "/ will be read-only; /data (frame-data partition) stays writable."
echo
echo "Now:  sudo reboot"
echo "After reboot check:  findmnt /  -> overlay ;  findmnt /data -> ext4 rw"
