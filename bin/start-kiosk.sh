#!/usr/bin/env bash
# Launch Chromium full-screen under the sway Wayland compositor in kiosk mode.
# Started from the tty1 autologin session (see scripts/install.sh).
#
# sway is used instead of cage because it can force-hide the pointer
# (`seat * hide_cursor`), which the packaged cage build cannot.
set -u

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
URL="http://127.0.0.1:8080/"

if mkdir -p /data/logs 2>/dev/null; then
  exec >>/data/logs/kiosk.log 2>&1
fi
echo "$(date -Is) start-kiosk: user=$(id -un) runtime=$XDG_RUNTIME_DIR"

# Call the real binary, not the Debian /usr/bin/chromium wrapper: the wrapper
# sources /etc/chromium.d/* which injects GOOGLE_API_KEY (activates GCM),
# --enable-remote-extensions and --load-extension=<bundled>. None of that is
# wanted on a kiosk and it's a likely crash source.
unset GOOGLE_API_KEY GOOGLE_DEFAULT_CLIENT_ID GOOGLE_DEFAULT_CLIENT_SECRET
CHROMIUM=""
for c in /usr/lib/chromium/chromium /usr/lib/chromium-browser/chromium-browser; do
  [ -x "$c" ] && CHROMIUM="$c" && break
done
[ -n "$CHROMIUM" ] || CHROMIUM="$(command -v chromium || command -v chromium-browser || true)"
if [ -z "$CHROMIUM" ]; then
  echo "chromium not found (apt install chromium)"; sleep 30; exit 1
fi
echo "$(date -Is) chromium: $CHROMIUM"
if ! command -v sway >/dev/null; then
  echo "sway not found (apt install sway swaybg)"; sleep 30; exit 1
fi

# wait for the local server to answer
for _ in $(seq 1 60); do
  curl -sf -o /dev/null "$URL" && break
  sleep 1
done

CHROME_FLAGS="--kiosk --ozone-platform=wayland --enable-features=UseOzonePlatform \
--disable-gpu --disable-gpu-compositing \
--no-sandbox --no-first-run --no-default-browser-check \
--disable-extensions --disable-component-extensions-with-background-pages \
--noerrdialogs --disable-infobars --disable-session-crashed-bubble \
--disable-features=Translate,TranslateUI,OptimizationHints,MediaRouter \
--overscroll-history-navigation=0 --disable-pinch \
--check-for-update-interval=31536000 --autoplay-policy=no-user-gesture-required \
--force-device-scale-factor=1 --mute-audio \
--enable-logging=stderr --v=1 \
--disable-background-networking --disable-sync --disable-component-update \
--disable-breakpad --disable-domain-reliability --disable-crash-reporter \
--password-store=basic --disk-cache-dir=/tmp/frame-cache --disk-cache-size=8388608"

SWAYCONF="$XDG_RUNTIME_DIR/frame-sway.conf"
cat > "$SWAYCONF" <<EOF
output * background #000000 solid_color
seat * hide_cursor 1
default_border none
default_floating_border none
xwayland disable
for_window [app_id=".*"] fullscreen enable, border none
for_window [title=".*"] fullscreen enable, border none
exec sh -c '$CHROMIUM $CHROME_FLAGS "$URL"; swaymsg exit'
EOF

# sway exits when Chromium exits (swaymsg exit); loop so a crash just respawns
while true; do
  sway -c "$SWAYCONF"
  echo "$(date -Is) sway exited ($?); respawning in 3s"
  sleep 3
done
