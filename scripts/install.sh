#!/usr/bin/env bash
# One-time setup on the Raspberry Pi. Run as a normal sudo-capable user.
#   git clone <repo> /opt/frame-tv-sync && sudo /opt/frame-tv-sync/scripts/install.sh
set -euo pipefail

APP_DIR=/opt/frame-tv-sync
APP_USER=frame

if [[ $EUID -ne 0 ]]; then echo "run with sudo" >&2; exit 1; fi

echo "==> packages"
apt-get update
apt-get install -y --no-install-recommends \
  chromium sway swaybg rclone cec-utils curl \
  python3 python3-venv python3-pip \
  fonts-dejavu-core ca-certificates

echo "==> user: $APP_USER"
id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --create-home "$APP_USER"
usermod -s /bin/bash "$APP_USER"                 # needs a login shell for tty1 autologin
usermod -aG video,render,tty,input "$APP_USER"
loginctl enable-linger "$APP_USER" || true

echo "==> python venv"
python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install --upgrade pip
"$APP_DIR/.venv/bin/pip" install -r "$APP_DIR/requirements.txt" || \
  "$APP_DIR/.venv/bin/pip" install Pillow   # HEIF support is optional

echo "==> data partition"
if ! mountpoint -q /data; then
  echo "!! /data is not a separate mount." >&2
  echo "!! Run scripts/setup-storage.sh (twice, with a reboot between) first." >&2
  exit 1
fi
mkdir -p /data/photos /data/secrets /data/logs
# live, editable config on the writable partition (survives Overlay FS)
[[ -f /data/config.toml ]] || cp "$APP_DIR/config.toml" /data/config.toml
chown -R "$APP_USER":"$APP_USER" /data
chmod 700 /data/secrets

echo "==> ownership"
chown -R "$APP_USER":"$APP_USER" "$APP_DIR"

echo "==> systemd units"
cp "$APP_DIR"/systemd/*.service "$APP_DIR"/systemd/*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable frame-serve.service frame-cec.service frame-sync.timer

echo "==> kiosk: autologin $APP_USER on tty1 -> start-kiosk.sh"
# A systemd service can't get a seat for cage on this OS; a tty1 autologin does.
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $APP_USER --noclear %I \$TERM
EOF
cat > "/home/$APP_USER/.bash_profile" <<EOF
if [ "\$(tty)" = "/dev/tty1" ] && [ -z "\${WAYLAND_DISPLAY:-}" ]; then
  exec $APP_DIR/bin/start-kiosk.sh
fi
EOF
chown "$APP_USER":"$APP_USER" "/home/$APP_USER/.bash_profile"
systemctl daemon-reload

echo "==> console: disable screen blanking"
if ! grep -q 'consoleblank=0' /boot/firmware/cmdline.txt 2>/dev/null; then
  sed -i 's/$/ consoleblank=0/' /boot/firmware/cmdline.txt || true
fi

echo "==> disable apt/man-db background timers"
# They can't achieve anything once Overlay FS is on (writes go to a RAM overlay
# and vanish on reboot) and just cost RAM. Updates are done manually — see the
# Maintenance section of the README.
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer man-db.timer 2>/dev/null || true

cat <<'EOF'

Done. Remaining manual steps:
  1. Create /data/secrets/gdrive-sa.json  (service-account key — see docs/gdrive-service-account.md)
  2. Create /data/secrets/rclone.conf     (see docs/gdrive-service-account.md)
  3. Test:   sudo -u frame /opt/frame-tv-sync/.venv/bin/python /opt/frame-tv-sync/bin/sync.py
  4. Tune /data/config.toml if you like (this copy stays editable after step 5).
  5. Enable Overlay FS:  sudo raspi-config -> Performance -> Overlay File System
     (also answer "yes" to making the boot partition read-only)
  6. Reboot.

To edit anything under / (e.g. update the code) later: raspi-config -> disable
Overlay FS -> reboot -> edit -> re-enable -> reboot. Files under /data, including
config.toml and photos, are always writable.

EOF
