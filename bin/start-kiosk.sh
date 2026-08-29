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

# cage draws its own compositor pointer that page CSS can't hide. Give wlroots
# a fully transparent cursor theme (generated once).
CURDIR="$HOME/.local/share/icons/frame-blank/cursors"
if [ ! -e "$CURDIR/left_ptr" ]; then
  mkdir -p "$CURDIR"
  python3 - "$CURDIR" <<'PY' || true
import struct, sys, os
d = sys.argv[1]
blob = (b"Xcur" + struct.pack("<III", 16, 0x00010000, 1)
        + struct.pack("<III", 0xfffd0002, 1, 28)
        + struct.pack("<IIIIIIIIII", 36, 0xfffd0002, 24, 1, 1, 1, 0, 0, 0, 0))
open(os.path.join(d, "left_ptr"), "wb").write(blob)
for n in ("default","pointer","arrow","top_left_arrow","xterm","text","hand1",
          "hand2","watch","left_ptr_watch","cross","crosshair","move","grab"):
    p = os.path.join(d, n)
    if not os.path.exists(p):
        os.symlink("left_ptr", p)
open(os.path.join(os.path.dirname(d), "index.theme"), "w").write(
    "[Icon Theme]\nName=frame-blank\n")
PY
fi
export XCURSOR_PATH="$HOME/.local/share/icons:/usr/share/icons"
export XCURSOR_THEME=frame-blank
export XCURSOR_SIZE=24

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
    --no-sandbox \
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
