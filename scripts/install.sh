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
  chromium cage rclone cec-utils curl \
  python3 python3-venv python3-pip \
  fonts-dejavu-core ca-certificates

echo "==> user: $APP_USER"
id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin "$APP_USER"
usermod -aG video,render,tty,input "$APP_USER"
loginctl enable-linger "$APP_USER" || true

echo "==> python venv"
python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install --upgrade pip
"$APP_DIR/.venv/bin/pip" install -r "$APP_DIR/requirements.txt" || \
  "$APP_DIR/.venv/bin/pip" install Pillow   # HEIF support is optional

echo "==> data dirs (put this on the USB stick mounted at /data)"
mkdir -p /data/photos /data/secrets /data/logs
chown -R "$APP_USER":"$APP_USER" /data
chmod 700 /data/secrets

echo "==> ownership"
chown -R "$APP_USER":"$APP_USER" "$APP_DIR"

echo "==> systemd units"
cp "$APP_DIR"/systemd/*.service "$APP_DIR"/systemd/*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable frame-serve.service frame-kiosk.service frame-cec.service frame-sync.timer

echo "==> console: disable screen blanking"
if ! grep -q 'consoleblank=0' /boot/firmware/cmdline.txt 2>/dev/null; then
  sed -i 's/$/ consoleblank=0/' /boot/firmware/cmdline.txt || true
fi

cat <<'EOF'

Done. Remaining manual steps:
  1. Create /data/secrets/gdrive-sa.json  (service-account key — see docs/gdrive-service-account.md)
  2. Create /data/secrets/rclone.conf     (see docs/gdrive-service-account.md)
  3. Test:   sudo -u frame /opt/frame-tv-sync/.venv/bin/python /opt/frame-tv-sync/bin/sync.py
  4. Enable Overlay FS:  sudo raspi-config  ->  Performance  ->  Overlay File System
  5. Reboot.

EOF
