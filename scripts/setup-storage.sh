#!/usr/bin/env bash
# Partition the boot medium for frame-tv-sync:
#   - grow the OS partition (p2) to a fixed size (default 8 GiB)
#   - give the rest of the disk to a writable ext4 /data partition (p3)
#
# Depends only on tools already in Raspberry Pi OS Lite (sfdisk, resize2fs,
# mkfs.ext4) so it works even though the fresh OS partition is nearly full.
#
# A partition-table change needs a reboot before the kernel will grow the
# filesystem, so run it TWICE:
#
#   curl -fsSL https://raw.githubusercontent.com/kierenwade/Photoframe/main/scripts/setup-storage.sh -o /tmp/setup-storage.sh
#   sudo bash /tmp/setup-storage.sh        # edits the table, then reboots
#   # ... wait for it to come back, reconnect ...
#   sudo bash /tmp/setup-storage.sh        # grows root, formats + mounts /data
#
# Override the OS partition size with:  sudo FRAME_ROOT_GB=6 bash /tmp/setup-storage.sh
set -euo pipefail

ROOT_GB="${FRAME_ROOT_GB:-8}"
LABEL="frame-data"
MNT="/data"

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

root_src=$(findmnt -no SOURCE /)
disk="/dev/$(lsblk -no PKNAME "$root_src")"
base=$(basename "$disk")
[[ -b $disk ]] || { echo "could not find the disk behind / ($root_src)" >&2; exit 1; }
case "$disk" in *[0-9]) pp=p ;; *) pp= ;; esac
rootpart="${disk}${pp}2"
datapart="${disk}${pp}3"

# ---------------------------------------------------------------- phase 2
# /data partition now exists as a block device -> finish the job.
if [[ -b $datapart ]]; then
  if mountpoint -q "$MNT" && grep -q "LABEL=$LABEL" /etc/fstab; then
    echo "storage already set up:"
    df -h / "$MNT"
    exit 0
  fi
  echo "== finalising =="
  resize2fs "$rootpart" || true
  # format unless the partition already carries our label (idempotent re-run).
  # wipefs first: a re-used card can leave a stale fs signature here, which
  # would otherwise make us skip mkfs and then fail to mount by label.
  if [[ "$(blkid -o value -s LABEL "$datapart" 2>/dev/null)" != "$LABEL" ]]; then
    wipefs -a "$datapart" || true
    mkfs.ext4 -F -L "$LABEL" "$datapart"
  fi
  mkdir -p "$MNT"
  grep -q "LABEL=$LABEL" /etc/fstab ||
    echo "LABEL=$LABEL  $MNT  ext4  defaults,noatime,commit=30,errors=remount-ro  0  2" >>/etc/fstab
  mountpoint -q "$MNT" || mount "$MNT"
  mkdir -p "$MNT"/photos "$MNT"/secrets "$MNT"/logs
  chmod 700 "$MNT/secrets"
  echo
  echo "done:"
  df -h / "$MNT"
  echo
  echo "Next:"
  echo "  sudo apt update && sudo apt install -y git"
  echo "  sudo git clone https://github.com/kierenwade/Photoframe.git /opt/frame-tv-sync"
  echo "  sudo /opt/frame-tv-sync/scripts/install.sh"
  exit 0
fi

# ---------------------------------------------------------------- phase 1
# table not changed yet (or changed but not rebooted).
if sfdisk -d "$disk" | grep -q "^${datapart} "; then
  echo "partition table already updated — reboot, then run this script again."
  exit 0
fi

sect_total=$(cat "/sys/block/$base/size")
root_start=$(cat "/sys/block/$base/${base}${pp}2/start")
root_cur=$(cat "/sys/block/$base/${base}${pp}2/size")

want=$((ROOT_GB * 2097152))            # GiB -> 512-byte sectors
((root_cur > want)) && want=$root_cur  # never shrink an already-larger root

root_end=$((root_start + want - 1))
data_start=$(((root_end + 2048) / 2048 * 2048))   # 1 MiB alignment

if ((data_start + 4194304 > sect_total)); then    # need >= 2 GiB left for /data
  echo "Not enough free space for a ${ROOT_GB} GiB OS partition plus /data." >&2
  echo "The root filesystem has probably auto-expanded to fill the whole card." >&2
  echo "Re-flash with growpart/resize disabled — see docs/tv-and-hardware.md." >&2
  exit 1
fi

echo "disk        : $disk  ($((sect_total / 2097152)) GiB)"
echo "OS  part    : $rootpart  -> ~${ROOT_GB} GiB (start $root_start unchanged)"
echo "data part   : $datapart  -> rest of disk, ext4, label $LABEL, mounted $MNT"
echo

# grow p2 in place (empty start field = keep start; filesystem untouched)
echo ", ${want}"        | sfdisk --no-reread --no-tell-kernel --force -N 2 "$disk"
# append p3 filling the remainder
echo "${data_start},,83" | sfdisk --no-reread --no-tell-kernel --force --append "$disk"
sync

echo
echo "Partition table written. Rebooting in 5s (Ctrl-C to cancel)."
echo "When it comes back, run this script ONE more time to finish."
sleep 5
reboot
