#!/usr/bin/env bash
# Push local changes to the Pi and restart the services. Run from your Mac.
#   ./scripts/deploy.sh frame-pi.local
set -euo pipefail

HOST="${1:?usage: deploy.sh <pi-host>}"
APP_DIR=/opt/frame-tv-sync

rsync -az --delete \
  --exclude '.git' --exclude '.venv' --exclude 'data' \
  ./ "root@${HOST}:${APP_DIR}/"

ssh "root@${HOST}" bash -s <<'EOF'
set -e
cp /opt/frame-tv-sync/systemd/*.service /opt/frame-tv-sync/systemd/*.timer /etc/systemd/system/
chown -R frame:frame /opt/frame-tv-sync
systemctl daemon-reload
systemctl restart frame-serve.service frame-kiosk.service
echo "deployed; kiosk restarting"
EOF
