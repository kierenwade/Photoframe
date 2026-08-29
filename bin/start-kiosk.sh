#!/usr/bin/env bash
# Launch Chromium full-screen under the cage Wayland kiosk compositor.
# Started from the tty1 autologin session (see scripts/install.sh).
set -u

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
URL="http://127.0.0.1:8080/"

# log to the writable partition when it's available
if mkdir -p /data/logs 2>/dev/null; then
  exec >>/data/logs/kiosk.log 2>&1
fi
echo "$(date -Is) start-kiosk: user=$(id -un) runtime=$XDG_RUNTIME_DIR"

CHROMIUM="$(command -v chromium || command -v chromium-browser || true)"
if [ -z "$CHROMIUM" ]; then
  echo "chromium not found (apt install chromium)"
  sleep 30
  exit 1
fi

# wait for the local server to answer
for _ in $(seq 1 60); do
  curl -sf -o /dev/null "$URL" && break
  sleep 1
done

# cage exits when Chromium exits; loop so a crash just respawns it
while true; do
  cage -- "$CHROMIUM" \
    --kiosk \
    --ozone-platform=wayland \
    --enable-features=UseOzonePlatform \
    --disable-gpu \
    --no-first-run --no-default-browser-check \
    --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
    --disable-features=Translate,TranslateUI \
    --overscroll-history-navigation=0 --disable-pinch \
    --check-for-update-interval=31536000 \
    --autoplay-policy=no-user-gesture-required \
    --force-device-scale-factor=1 \
    "$URL"
  echo "$(date -Is) cage/chromium exited ($?); respawning in 3s"
  sleep 3
done
