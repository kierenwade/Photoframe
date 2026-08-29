#!/usr/bin/env bash
# Launch Chromium full-screen under the cage Wayland kiosk compositor.
set -eu

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
URL="http://localhost:8080/"

CHROMIUM="$(command -v chromium || command -v chromium-browser || true)"
if [ -z "$CHROMIUM" ]; then
  echo "chromium not found (apt install chromium)" >&2
  exit 1
fi

# Wait for the local server to answer before opening the page.
for _ in $(seq 1 30); do
  if curl -sf -o /dev/null "$URL"; then break; fi
  sleep 1
done

exec cage -- "$CHROMIUM" \
  --kiosk --incognito --noerrdialogs --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=Translate,TranslateUI \
  --overscroll-history-navigation=0 --disable-pinch \
  --check-for-update-interval=31536000 \
  --autoplay-policy=no-user-gesture-required \
  --force-device-scale-factor=1 \
  --ozone-platform=wayland \
  --app="$URL"
