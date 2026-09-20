#!/usr/bin/env bash
# Enable a read-only root (Overlay FS) while keeping /data writable.
#
# raspi-config's Overlay FS uses `overlayroot=tmpfs`, whose default recurse=1
# also freezes the frame-data partition (writes to /data would be RAM-only and
# lost on reboot). We force recurse=0 so only / is read-only.
#
# Safe to re-run, including on a device where overlay was previously disabled
# by setting `overlayroot=disabled` in cmdline.txt (the standard way to turn
# it off for maintenance) - this normalises whatever value is there.
#
#   sudo /opt/frame-tv-sync/scripts/enable-overlay.sh
#   sudo reboot
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
CMDLINE=/boot/firmware/cmdline.txt

# The overlayroot *package* (and its initramfs hook) only needs installing
# once; /etc/overlayroot.conf existing is proof it already is, regardless of
# what cmdline.txt currently says (disabled, tmpfs, or absent).
if [[ ! -f /etc/overlayroot.conf ]]; then
  echo "== installing overlayroot via raspi-config =="
  raspi-config nonint do_overlayfs 0 || {
    echo "!! nonint call failed — enable it in 'sudo raspi-config' → Performance →" >&2
    echo "!! Overlay File System, do NOT reboot, then run this script again." >&2
    exit 1
  }
fi

mount -o remount,rw /boot/firmware
if grep -q 'overlayroot=' "$CMDLINE"; then
  # replace whatever's there now (disabled, tmpfs, tmpfs:recurse=1, ...)
  sed -i -E 's/overlayroot=[^ ]*/overlayroot=tmpfs:recurse=0/' "$CMDLINE"
else
  sed -i 's/$/ overlayroot=tmpfs:recurse=0/' "$CMDLINE"
fi
mount -o remount,ro /boot/firmware || true

echo
echo "cmdline: $(grep -o 'overlayroot=[^ ]*' "$CMDLINE" || echo '(not set!)')"
echo "/ will be read-only; /data (frame-data partition) stays writable."
echo
echo "Now:  sudo reboot"
echo "After reboot check:  findmnt /  -> overlay ;  findmnt /data -> ext4 rw"
